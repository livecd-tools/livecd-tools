%include /usr/share/livecd-tools/livecd-fedora-8-desktop.ks
part / --size 8000

# customize repo configuration for local builds
# repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch


%packages

# games

# traditional (big)

bzflag
openarena
#croquet (pending)
#vdrift
nethack-vultures
freedoom
beneath-a-steel-sky-cd
flight-of-the-amazon-queen-cd
supertuxkart
scorched3d
neverball
lincity-ng
freeciv
pinball
asc
asc-music
vegastrike 
FlightGear 
nexuiz
torcs
tremulous
frozen-bubble
xpilot-ng
crossfire-client
wormux
wesnoth
gl-117
supertux
manaworld
freedroidrpg
maniadrive
maniadrive-music
abuse
worminator
armacycles-ad
blobAndConquer
boswars
warzone2100
widelands
freecol
astromenace
egoboo

# traditional (small)

nethack
openlierox
clanbomber
liquidwar
rogue
ularn
bsd-games
gnubg
gnugo
quarry
bombardier
ballz
blobwars
hedgewars
machineball
Ri-li
stormbaancoureur
quake3
vavoom
rott-shareware
londonlaw
nazghul-haxima
scorchwentbonkers
seahorse-adventures

# arcade classics(ish) (big)

raidem
raidem-music
duel3
lmarbles
trackballs
trackballs-music
auriferous

# arcade classics(ish) (small)

lacewing
njam
#(xgalaga renamed)
xgalaxy 
ballbuster
tecnoballz
dd2
KoboDeluxe
Maelstrom
methane
zasx
shippy
seahorse-adventures

# falling blocks games (small) 

fbg
gemdropx
crystal-stacker
crack-attack 

# puzzles (big)
enigma
fillets-ng
pingus

# puzzles (small)

magicor
mirrormagic
rocksndiamonds
escape

# card games

poker2d

# educational/simulation

celestia
stellarium
tuxpaint
tuxpaint-stamps
tuxtype2
gcompris
childsplay
bygfoot

# kde based games
ksirk
taxipilot
poker2d-kde

# utilities

dosbox
games-menus
wget

%end
