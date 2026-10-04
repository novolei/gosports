#!/bin/bash
# Batch 1 of the promo recordings (see promo/rec.sh).  Matches and gags are recorded at 1440p (2560x1440; 4K was 11x slower than real time) so the edit can punch in
# without softness; menus / results at 1080p.  Sequential.
cd "$(dirname "$0")/.."
R=promo/rec.sh
K=2560x1440
P="--profile=user://promo_profile.json"
CAM="--cam=3.9,11.8,50"                       # a little closer than the broadcast default (4.2 / 13 / 54)
C="--cleanhud --skipvs $CAM"

# ---- full matches with the player HUD (the human bot plays P1 through the real input map)
$R m1_day     130 $K -- --screen=match --humanbot --mode=solo --diff=2 --points=11 --team_a=m,bear --team_b=snow,wang --cleanhud $CAM
$R m3_sunset  130 $K -- --screen=match --humanbot --mode=solo --diff=2 --points=11 --court=sunset --deco=festival --ballskin=candy --trail=sakura --net=heart --team_a=sakura,shiba --team_b=rhino,moose $C
$R m2_night    90 $K -- --screen=match --humanbot --mode=solo --diff=2 --points=11 --court=night --deco=press --ballskin=neon --trail=rainbow --net=star --team_a=tutu,panda --team_b=ninja_red,ninja_blue $C
$R ai_dawn     80 $K -- --screen=match --autoplay --points=9 --court=dawn --deco=bunting --replay --team_a=monkey,hippo --team_b=croc,fawn $C

# ---- the gags (forced by the dev hooks; banter_team = the team that wins the point, the other side's partner erupts)
$R g_fish      28 $K -- --screen=match --mode=solo --servescale=0.2 --propid=fish $C
$R g_punch_ours 16 $K -- --screen=match --humanbot --mode=solo --banter=punch --banter_team=1 $C
$R g_sardine_ours 16 $K -- --screen=match --humanbot --mode=solo --banter=sardine --banter_team=1 $C
$R g_punch_slow 36 $K -- --screen=match --humanbot --mode=solo --banter=punch --banter_team=1 --timescale=0.4 $C
$R g_sardine_slow 36 $K -- --screen=match --humanbot --mode=solo --banter=sardine --banter_team=1 --timescale=0.4 $C
$R g_punch_opp 16 $K -- --screen=match --humanbot --mode=solo --banter=punch --banter_team=0 $C
$R g_sardine_opp 16 $K -- --screen=match --humanbot --mode=solo --banter=sardine --banter_team=0 $C
$R g_final_punch 24 $K -- --screen=match --humanbot --mode=solo --banter=punch --banter_final --banter_team=1 $C
$R g_highfive  12 $K -- --screen=match --humanbot --mode=solo --banter=highfive --banter_team=0 $C
$R g_dance_a   12 $K -- --screen=match --humanbot --mode=solo --banter=dance --dance=dance_a --banter_team=0 $C
$R g_dance_b   12 $K -- --screen=match --humanbot --mode=solo --banter=dance --dance=dance_b --banter_team=0 $C
$R g_dance_c   12 $K -- --screen=match --humanbot --mode=solo --banter=dance --dance=dance_c --banter_team=0 $C
$R g_clap      10 $K -- --screen=match --humanbot --mode=solo --banter=clap --banter_team=0 $C

# ---- features
$R g_hawk_out  18 $K -- --screen=match --humanbot --mode=solo --hawkdemo=out $C
$R g_hawk_in   18 $K -- --screen=match --humanbot --mode=solo --hawkdemo=in $C
$R g_fever     28 $K -- --screen=match --humanbot --mode=solo --fever $C
$R g_combo     16 $K -- --screen=match --humanbot --mode=solo --combodemo $C
$R g_aim       30 $K -- --screen=match --humanbot --mode=solo --aimdemo=0.7,-0.7 $C

# ---- menus and results (lived-in profile), 1080p
$R menu_main    9 -- --screen=menu $P
$R menu_main_en 7 -- --screen=menu --lang=en $P
$R menu_mode    7 -- --screen=menu --page=mode $P
$R menu_career0 7 -- --screen=menu --page=career --tab=0 $P
$R menu_career1 7 -- --screen=menu --page=career --tab=1 $P
$R menu_career2 7 -- --screen=menu --page=career --tab=2 $P
$R menu_col0    6 -- --screen=menu --page=career --tab=1 --colkind=0 $P
$R menu_col3    6 -- --screen=menu --page=career --tab=1 --colkind=3 $P
$R menu_col4    6 -- --screen=menu --page=career --tab=1 --colkind=4 $P
$R menu_settings 6 -- --screen=menu --page=settings $P
$R menu_howto   6 -- --screen=menu --page=howto $P
$R res_win     16 -- --screen=results $P
$R res_loss     9 -- --screen=results --resultloss $P

# ---- phone layout (20:9)
$R touch_match 28 2400x1080 -- --screen=match --humanbot --mode=solo --touch --cleanhud --skipvs
$R touch_menu   8 2400x1080 -- --screen=menu --touch $P
echo "BATCH1 DONE"
