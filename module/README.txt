The minimal wiring in your game — 4 things:

1. Startup (once, after your screen and palette are set up):

moveq   #5,d0               ; ← your game's plane count
lea     MyBitplane0,a0    ; your plane 0 chip RAM address
lea     MyPalette,a1      ; your 32-word DC.W palette table
lea     MyCopperList,a2   ; your copper list (module saves this to restore later)
jsr     VHS_Init          ; d0=0 means not enough chip RAM

2. Your VBlank handler (replaces your copper install when effect is active):

tst.b   VHS_StateActive   ; zero cost — just a byte test
beq     .skip
jsr     VHS_DoFrame        ; does everything; d0=0 when done+copper restored
bra     .done
.skip:
; ... your normal copper update ...
.done:

3. Trigger/untrigger (from anywhere — game logic, keyboard handler, etc.):

jsr     VHS_StartEffect   ; snapshot palette, begin fade-in
jsr     VHS_StopEffect    ; begin fade-out

4. Shutdown:

jsr     VHS_Free