#!/bin/bash
# Batch 2: the umpire's props and reactions (the "gag moments" section), 4K.  Starts after batch 1 (one override.cfg at a time).
cd "$(dirname "$0")/.."
until grep -q "BATCH1 DONE" promo_work/rec_batch1.log 2>/dev/null; do sleep 10; done
R=promo/rec.sh
K=2560x1440
CAM="--cam=3.9,11.8,50"
C="--cleanhud --skipvs"
UCAM="--refcam=-3.3,2.7,0.9,-6.6,2.45,0.0,38"           # close-up of the umpire on the chair (-6.6, 0, 0), seen from the court side

# umpire reactions, one animal each (the dev clip loops forever)
$R ref_shake   7 $K -- --screen=match --mode=solo --ref=panda   --refclip=ref_shake   $C $UCAM
$R ref_sigh    7 $K -- --screen=match --mode=solo --ref=rhino   --refclip=ref_sigh    $C $UCAM
$R ref_wow     6 $K -- --screen=match --mode=solo --ref=monkey  --refclip=ref_wow     $C $UCAM
$R ref_whistle 6 $K -- --screen=match --mode=solo --ref=hippo   --refclip=ref_whistle $C $UCAM
$R ref_throw   7 $K -- --screen=match --mode=solo --ref=tutu    --refclip=ref_throw_r $C $UCAM
$R ref_wipe    6 $K -- --screen=match --mode=solo --ref=shiba   --refclip=ref_wipe    $C $UCAM

# every prop the umpire can throw, lined up in front of the camera
$R g_propshow  6 $K -- --screen=match --mode=solo --propshow --refcam=0,1.35,8.6,0,1.1,5,44 $C

# warnings with different props (timers shrunk: --servescale)
$R g_prop_banana  16 $K -- --screen=match --mode=solo --servescale=0.06 --propid=banana  $C $CAM
$R g_prop_duck    16 $K -- --screen=match --mode=solo --servescale=0.06 --propid=duck    $C $CAM
$R g_prop_slipper 16 $K -- --screen=match --mode=solo --servescale=0.06 --propid=slipper $C $CAM
$R g_prop_hammer  16 $K -- --screen=match --mode=solo --servescale=0.06 --propid=hammer  $C $CAM
$R g_prop_pencil  16 $K -- --screen=match --mode=solo --servescale=0.06 --propid=pencil  $C $CAM
$R g_prop_fish2   18 $K -- --screen=match --mode=solo --servescale=0.06 --propid=fish    $C $CAM
echo "BATCH2 DONE"
