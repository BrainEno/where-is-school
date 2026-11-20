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
PROJECTION = Threshold("projection_room", "ProjectionRoom", "02", "投影准备室", "PROJECTION", (2.79, 0, -30), 0,
                       (64, 66, 85), (99, 100, 127))
COMPUTER = Threshold("computer_room", "ComputerRoom", "02", "计算机教室", "COMPUTER LAB", (5.06, 0, -30), 0,
                     (49, 68, 69), (105, 123, 101))
VACANT = Threshold("vacant_office", "VacantOffice", "03", "空办公室", "STAFF WORKROOM", (-14.25, 3.6, -17.72), 90,
                   (69, 59, 87), (114, 105, 132))
PRINCIPAL = Threshold("principal_office", "PrincipalOffice", "03", "校长室", "PRINCIPAL", (2.68, 3.6, -45), 0,
                      (67, 52, 71), (134, 96, 76))
WASH_02 = Threshold("restroom_02", "Restroom02", "02", "厕所", "RESTROOM", (29, 0, -27.75), -90,
                    (62, 71, 61), (124, 125, 85), False)
WASH_03 = Threshold("restroom_03", "Restroom03", "03", "厕所", "RESTROOM", (20.65, 3.6, -42.75), -90,
                    (60, 53, 77), (117, 101, 121), False)
ANNEXES = (ARCHIVE, PLAN_ROOM, PROJECTION, COMPUTER, VACANT, PRINCIPAL)
UPPER_WASHES = (WASH_02, WASH_03)
THRESHOLDS = ANNEXES + UPPER_WASHES
