"""Measured corridor faces for the optional school rooms, in hall coordinates.

Faces point into the hall (+Z in door-local space). Only the corridor-facing
placement lives here; interior blocking and dialogue are authored separately.
"""
from dataclasses import dataclass
from math import cos, radians, sin


@dataclass(frozen=True)
class Threshold:
    id: str
    name: str
    floor: str
    title: str
    english: str
    pos: tuple[float, float, float]
    yaw: int
    trim: tuple[int, int, int]
    leaf: tuple[int, int, int]
    gated: bool = True

    @property
    def parent(self):
        return {"01": "GroundFloor", "02": "LowerFloor", "03": "UpperFloor"}[self.floor]

    def point(self, x, y, z):
        c, s = cos(radians(self.yaw)), sin(radians(self.yaw))
        a, b, d = self.pos
        return a + x * c + z * s, b + y, d - x * s + z * c


ARCHIVE = Threshold("archive", "Archive", "01", "档案室", "ARCHIVE", (-14.48, -3.4, 10.55), 0,
                    (74, 56, 62), (127, 91, 71))
PLAN_ROOM = Threshold("plan_room", "PlanRoom", "01", "图纸室", "PLAN ROOM", (-10.77, -3.4, 10.55), 0,
                      (42, 66, 73), (84, 113, 112))
# The screen on 01 hides the aperture until the player rounds the laboratory return.
PROJECTION = Threshold("projection_room", "ProjectionRoom", "01", "投影准备室", "PROJECTION", (-23.2, -3.4, 8.02), -90,
                       (50, 43, 59), (81, 54, 65))
# This gap is the pier between 104 and 105, across from the yard stair.
COMPUTER = Threshold("computer_room", "ComputerRoom", "02", "计算机教室", "COMPUTER LAB", (17.37, 0, -30), 0,
                     (43, 66, 67), (78, 102, 93))
VACANT = Threshold("vacant_office", "VacantOffice", "02", "空办公室", "STAFF WORKROOM", (2.1, 0, -18.68), -90,
                   (103, 98, 99), (174, 159, 147))
PRINCIPAL = Threshold("principal_office", "PrincipalOffice", "03", "校长室", "PRINCIPAL", (2.68, 3.6, -45), 0,
                      (67, 52, 71), (134, 96, 76))
WASH_02 = Threshold("restroom_02", "Restroom02", "02", "厕所", "RESTROOM", (29, 0, -27.75), -90,
                    (62, 71, 61), (124, 125, 85), False)
WASH_03 = Threshold("restroom_03", "Restroom03", "03", "厕所", "RESTROOM", (20.65, 3.6, -42.75), -90,
                    (60, 53, 77), (117, 101, 121), False)
ANNEXES = (ARCHIVE, PLAN_ROOM, PROJECTION, COMPUTER, VACANT, PRINCIPAL)
UPPER_WASHES = (WASH_02, WASH_03)
THRESHOLDS = ANNEXES + UPPER_WASHES

# No room-use labels on these hall leaves. The plate, handle and inset are the clues.
UNMARKED_ANNEXES = frozenset(r.id for r in (PROJECTION, COMPUTER, VACANT, PRINCIPAL))
