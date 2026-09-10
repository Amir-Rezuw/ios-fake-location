#!/usr/bin/env python3
"""teleportd - bridges the Teleport iOS app to the device's location-simulation service.

The iPhone app cannot change its own system location, so it sends the coordinate it
wants here instead. This daemon holds a DVT LocationSimulation channel open against the
tethered device for as long as it runs; the simulated location is only in effect while
that channel is alive, which is why this is a resident process rather than a one-shot
command.

Requires a running tunnel, started separately as root:

    sudo pymobiledevice3 remote tunneld
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import signal
import socket
from dataclasses import dataclass, asdict
from typing import Any, Optional

from pymobiledevice3.exceptions import TunneldConnectionError
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
from pymobiledevice3.tunneld.api import TUNNELD_DEFAULT_ADDRESS, get_tunneld_devices

SERVICE_TYPE = "_teleport._tcp"
SERVICE_NAME = "Teleport Agent"

# The device occasionally lets a simulated location lapse; re-asserting it costs one
# DTX message and keeps the spoof pinned without the app having to re-send.
REASSERT_INTERVAL = 25.0
TUNNEL_POLL_INTERVAL = 3.0

logger = logging.getLogger("teleportd")


class Stage:
    """Lifecycle of the bridge, mirrored verbatim by the iOS app's `Stage` enum."""

    TUNNEL_OFFLINE = "tunnelOffline"
    NO_DEVICE = "noDevice"
    CONNECTING = "connecting"
    READY = "ready"
    SPOOFING = "spoofing"
    ERROR = "error"


@dataclass
class Status:
    stage: str = Stage.TUNNEL_OFFLINE
    device: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    place: Optional[str] = None
    detail: Optional[str] = None

    def payload(self) -> bytes:
        return json.dumps(asdict(self)).encode() + b"\n"


class DeviceBridge:
    """Owns the connection to the device and the location-simulation channel.

    Everything here runs on one asyncio loop and is serialized behind `_lock`, so the
    DTX channel is never touched by two client connections at once.
    """

    def __init__(self) -> None:
        self.status = Status()
        self._lock = asyncio.Lock()
        self._rsd: Optional[RemoteServiceDiscoveryService] = None
        self._dvt: Optional[DvtProvider] = None
        self._simulation: Optional[LocationSimulation] = None
        self._pinned: Optional[tuple[float, float]] = None
        self._listeners: set[asyncio.Queue[Status]] = set()

    # -- status fan-out ---------------------------------------------------------

    def subscribe(self) -> asyncio.Queue[Status]:
        queue: asyncio.Queue[Status] = asyncio.Queue()
        self._listeners.add(queue)
        queue.put_nowait(self.status)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[Status]) -> None:
        self._listeners.discard(queue)

    def _publish(self, **changes: Any) -> None:
        previous = asdict(self.status)
        for key, value in changes.items():
            setattr(self.status, key, value)
        if asdict(self.status) == previous:
            return  # reconnect polling would otherwise log the same line forever

        logger.info(
            "%s%s",
            self.status.stage,
            f" - {self.status.detail}" if self.status.detail else "",
        )
        for queue in self._listeners:
            queue.put_nowait(self.status)

    # -- connection lifecycle --------------------------------------------------

    async def connect(self) -> bool:
        """Attach to the first tunnelled device and open a location channel.

        Returns True when a live simulation channel is available. Safe to call
        repeatedly; a healthy connection is left untouched.
        """
        if self._simulation is not None:
            return True

        if self.status.stage not in (Stage.TUNNEL_OFFLINE, Stage.NO_DEVICE):
            # Already-failed states re-poll on a timer; announcing each retry would
            # flap the phone's status pill between "connecting" and the failure.
            self._publish(stage=Stage.CONNECTING, detail="Reaching the device")
        try:
            devices = await get_tunneld_devices(TUNNELD_DEFAULT_ADDRESS)
        except TunneldConnectionError:
            self._publish(
                stage=Stage.TUNNEL_OFFLINE,
                device=None,
                detail="Run: sudo pymobiledevice3 remote tunneld",
            )
            return False

        if not devices:
            self._publish(
                stage=Stage.NO_DEVICE,
                device=None,
                detail="No trusted device on the tunnel",
            )
            return False

        rsd, *extra = devices
        for spare in extra:
            with contextlib.suppress(Exception):
                await spare.close()

        try:
            dvt = DvtProvider(rsd)
            await dvt.__aenter__()
            simulation = LocationSimulation(dvt)
            await simulation.__aenter__()
        except Exception as error:  # noqa: BLE001 - surfaced to the phone verbatim
            with contextlib.suppress(Exception):
                await rsd.close()
            self._publish(stage=Stage.ERROR, detail=f"{type(error).__name__}: {error}")
            return False

        self._rsd, self._dvt, self._simulation = rsd, dvt, simulation
        self._publish(stage=Stage.READY, device=await device_label(rsd), detail=None)
        return True

    async def _teardown(self) -> None:
        for resource in (self._simulation, self._dvt):
            if resource is not None:
                with contextlib.suppress(Exception):
                    await resource.__aexit__(None, None, None)
        if self._rsd is not None:
            with contextlib.suppress(Exception):
                await self._rsd.close()
        self._simulation = self._dvt = self._rsd = None

    # -- commands --------------------------------------------------------------

    async def set_location(self, latitude: float, longitude: float, place: Optional[str]) -> None:
        async with self._lock:
            if not await self.connect():
                return
            assert self._simulation is not None
            try:
                await self._simulation.set(latitude, longitude)
            except Exception as error:  # noqa: BLE001
                await self._teardown()
                self._publish(stage=Stage.ERROR, detail=f"{type(error).__name__}: {error}")
                return
            self._pinned = (latitude, longitude)
            self._publish(
                stage=Stage.SPOOFING,
                latitude=latitude,
                longitude=longitude,
                place=place,
                detail=None,
            )

    async def clear_location(self) -> None:
        async with self._lock:
            if self._simulation is None:
                self._pinned = None
                return
            try:
                await self._simulation.clear()
            except Exception as error:  # noqa: BLE001
                await self._teardown()
                self._publish(stage=Stage.ERROR, detail=f"{type(error).__name__}: {error}")
                return
            self._pinned = None
            self._publish(
                stage=Stage.READY,
                latitude=None,
                longitude=None,
                place=None,
                detail=None,
            )

    async def close(self) -> None:
        """Drop the device connection."""
        async with self._lock:
            await self._teardown()

    async def refresh(self) -> None:
        """Re-probe the device when nothing is pinned, so the phone sees liveness."""
        async with self._lock:
            if self._pinned is None:
                await self.connect()

    # -- background upkeep -----------------------------------------------------

    async def run_upkeep(self) -> None:
        """Re-assert a pinned location and reconnect after the device disappears."""
        while True:
            # Re-asserting a healthy pin can be leisurely, but a pin with no live
            # channel needs to be restored fast — that's the window where the real GPS
            # shows through, e.g. right after the USB cable is pulled and the tunnel
            # has to come back over Wi-Fi.
            healthy = self._pinned is not None and self._simulation is not None
            await asyncio.sleep(REASSERT_INTERVAL if healthy else TUNNEL_POLL_INTERVAL)
            async with self._lock:
                pinned = self._pinned
                if pinned is None:
                    if self._simulation is None:
                        await self.connect()
                    continue

                if self._simulation is None and not await self.connect():
                    continue
                assert self._simulation is not None
                try:
                    await self._simulation.set(*pinned)
                except Exception as error:  # noqa: BLE001
                    await self._teardown()
                    self._publish(
                        stage=Stage.ERROR,
                        detail=f"Lost the device ({type(error).__name__})",
                    )


async def serve_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    bridge: DeviceBridge,
) -> None:
    peer = writer.get_extra_info("peername")
    logger.info("app connected from %s", peer)
    queue = bridge.subscribe()

    async def push_status() -> None:
        while True:
            status = await queue.get()
            writer.write(status.payload())
            await writer.drain()

    pusher = asyncio.create_task(push_status())
    try:
        while line := await reader.readline():
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue

            command = message.get("command")
            if command == "set":
                await bridge.set_location(
                    float(message["latitude"]),
                    float(message["longitude"]),
                    message.get("name"),
                )
            elif command == "clear":
                await bridge.clear_location()
            elif command == "status":
                await bridge.refresh()
                queue.put_nowait(bridge.status)
    except (ConnectionResetError, asyncio.IncompleteReadError):
        pass
    finally:
        pusher.cancel()
        bridge.unsubscribe(queue)
        with contextlib.suppress(Exception):
            writer.close()
            await writer.wait_closed()
        logger.info("app disconnected from %s", peer)


async def device_label(rsd: RemoteServiceDiscoveryService) -> Optional[str]:
    """The device's user-visible name, falling back to its model identifier."""
    with contextlib.suppress(Exception):
        if name := await rsd.get_value(key="DeviceName"):
            return str(name)
    return getattr(rsd, "product_type", None)


async def advertise(port: int) -> asyncio.subprocess.Process:
    """Publish the service through mDNSResponder.

    Using the system's own responder rather than a Python mDNS stack avoids two
    processes contending for port 5353, and it keeps the daemon dependency-free.
    """
    # A previous run killed with SIGKILL leaves its responder behind, still advertising
    # a port nothing is listening on — the app would sit forever on "connecting".
    stale = await asyncio.create_subprocess_exec(
        "pkill",
        "-f",
        f"dns-sd -R {SERVICE_NAME} {SERVICE_TYPE}",
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )
    await stale.wait()

    return await asyncio.create_subprocess_exec(
        "dns-sd",
        "-R",
        SERVICE_NAME,
        SERVICE_TYPE,
        "local",
        str(port),
        f"host={socket.gethostname()}",
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(message)s", datefmt="%H:%M:%S")

    bridge = DeviceBridge()
    server = await asyncio.start_server(
        lambda r, w: serve_client(r, w, bridge), host="0.0.0.0", port=0
    )
    port = server.sockets[0].getsockname()[1]
    responder = await advertise(port)

    logger.info("listening on port %d, advertised as %r", port, SERVICE_NAME)
    upkeep = asyncio.create_task(bridge.run_upkeep())
    await bridge.connect()

    # Restore the real GPS on `kill` as well as on Ctrl-C.
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signal_name in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(signal_name, stop.set)

    try:
        await stop.wait()
    finally:
        # Deliberately not `async with server` / `wait_closed()`: that waits for every
        # connected app to disconnect first, so a running phone would stall shutdown
        # and the location would never be handed back.
        server.close()
        upkeep.cancel()
        # Let upkeep finish unwinding first; it holds the bridge lock that
        # clear_location needs, and waiting here keeps shutdown prompt.
        with contextlib.suppress(asyncio.CancelledError):
            await upkeep
        await bridge.clear_location()
        await bridge.close()
        with contextlib.suppress(ProcessLookupError):
            responder.terminate()


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(main())
