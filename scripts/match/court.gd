class_name Court
extends RefCounted
## Court geometry + physical constants shared by ball, athletes, AI and camera.
## Axes: +x = right (as seen from the near team's camera), +z = towards the camera, net on z = 0.
## Team 0 ("A", near the camera) owns z > 0, team 1 ("B", far) owns z < 0.

const HALF_W := 4.5            # half width of the playing court
const HALF_D := 7.0            # half length (net to end line)
const NET_TOP := 2.2           # top of the net tape
const NET_X := 5.0             # post position
const ATTACK_LINE := 2.8
const BALL_R := 0.14
const GRAVITY := 12.0
const FREE_ZONE := 3.5         # run-off area beyond the lines
const PLAYER_MAX_X := 8.0
const PLAYER_MAX_Z := 11.0
const FLOOR_BOUNCE := 0.62

## The SIDE camera (C key, docs/DESIGN.md 38): the "main camera" of a real volleyball broadcast - high, on the +x side line, in line with the net
## (the net is seen end-on, the teams stand left / right), a long lens, the whole court in the picture. The umpire chair and the benches are on
## the opposite side line (-x), exactly like the real thing. 18 m / 11 m / fov 34 keeps the whole court (and the servers) in the picture at 16:9
## and 20:9; the far half of the court is ~60-85 px/m here instead of ~13 px/m behind the end line. `--sidecam=dist,height,fov[,focus_y]` tunes it.
const CAM_SIDE_DIST := 18.0
const CAM_SIDE_H := 11.0
const CAM_SIDE_FOV := 34.0

static func team_sign(team: int) -> float:
	## +1 for team 0 (z > 0), -1 for team 1
	return 1.0 if team == 0 else -1.0


static func side_of(z: float) -> int:
	return 0 if z >= 0.0 else 1


static func in_court(p: Vector3, margin := 0.0) -> bool:
	return absf(p.x) <= HALF_W + margin and absf(p.z) <= HALF_D + margin


## position in "team space": +z always points from the net to the team's own end line
static func to_team(team: int, p: Vector3) -> Vector3:
	return Vector3(p.x * team_sign(team), p.y, p.z * team_sign(team))


static func from_team(team: int, p: Vector3) -> Vector3:
	return to_team(team, p)   # the mapping is its own inverse


## flight of a ball under gravity only. Returns velocity to go from p0 to p1 in time t.
static func solve_velocity(p0: Vector3, p1: Vector3, t: float) -> Vector3:
	var d := p1 - p0
	return Vector3(d.x / t, d.y / t + 0.5 * GRAVITY * t, d.z / t)


## does the parabola from p0 with v clear the net (when it crosses z = 0)?
static func net_clearance(p0: Vector3, v: Vector3) -> float:
	## returns height of the ball centre at the net plane minus (NET_TOP + BALL_R); big = clears; < 0 = hits net
	## (+INF when the trajectory never crosses the plane)
	if absf(v.z) < 0.0001:
		return INF
	var t := -p0.z / v.z
	if t <= 0.0:
		return INF
	var y := p0.y + v.y * t - 0.5 * GRAVITY * t * t
	return y - (NET_TOP + BALL_R)


## time until the ball centre reaches height h (descending branch); returns -1 if it never does
static func time_to_height(y0: float, vy: float, h: float) -> float:
	var disc := vy * vy + 2.0 * GRAVITY * (y0 - h)
	if disc < 0.0:
		return -1.0
	return (vy + sqrt(disc)) / GRAVITY


static func pos_at(p0: Vector3, v: Vector3, t: float) -> Vector3:
	return Vector3(p0.x + v.x * t, p0.y + v.y * t - 0.5 * GRAVITY * t * t, p0.z + v.z * t)
