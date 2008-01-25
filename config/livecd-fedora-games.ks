%include /usr/share/livecd-tools/livecd-fedora-desktop.ks
part / --size 8000

# customize repo configuration for local builds
# repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch


%packages

# games

# traditional (big)

abuse
alienarena
armacycles-ad
asc
asc-music
astromenace
beneath-a-steel-sky-cd
blobAndConquer
boswars
bzflag
#croquet (pending)
crossfire-client
egoboo
FlightGear
flight-of-the-amazon-queen-cd
freeciv
freecol
freedoom
freedroidrpg
frozen-bubble
gl-117
lincity-ng
manaworld
maniadrive
maniadrive-music
nethack-vultures
neverball
nexuiz
openarena
pinball
scorched3d
supertux
supertuxkart
torcs
tremulous
#vdrift
vegastrike
warzone2100
wesnoth
widelands
worminator
wormux
xpilot-ng

# traditional (small)

ballz
blobwars
bombardier
bsd-games
clanbomber
gnubg
gnugo
hedgewars
liquidwar
londonlaw
machineball
nazghul-haxima
nethack
openlierox
quake3
quake3-demo
quarry
Ri-li
rogue
rott-shareware
scorchwentbonkers
seahorse-adventures
stormbaancoureur
ularn
urbanterror
vavoom
worldofpadman

# arcade classics(ish) (big)

auriferous
duel3
lmarbles
raidem
raidem-music
trackballs
trackballs-music
uqm
uqm-content-3domusic
uqm-content-voice

# arcade classics(ish) (small)

ballbuster
dd2
KoboDeluxe
lacewing
Maelstrom
methane
njam
seahorse-adventures
shippy
tecnoballz
#(xgalaga renamed)
xgalaxy
zasx

# falling blocks games (small) 

crack-attack
crystal-stacker
fbg
gemdropx
gweled

# puzzles (big)
enigma
fillets-ng
pingus

# puzzles (small)

escape
magicor
mirrormagic
pychess
rocksndiamonds

# card games

poker2d

# educational/simulation

bygfoot
celestia
childsplay
gcompris
stellarium
tuxpaint
tuxpaint-stamps
tuxtype2

# kde based games
ksirk
poker2d-kde
taxipilot

# utilities

dosbox
games-menus
wget

%end
