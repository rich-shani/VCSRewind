*******************************************************************************
*
*   VHS_TEST.S  —  Amiga 68000 Assembly
*   Test Program for VHS_NEW Effect Module
*
*   Displays colored bars and applies VHS effect on F10 key press
*
*******************************************************************************

    OPT O+
    OPT W-

*=============================================================================
* HARDWARE EQUATES
*=============================================================================

CUSTOM          EQU     $DFF000
INTENA          EQU     $09A
INTREQ          EQU     $09C
DMACONR         EQU     $002
DMACON          EQU     $096
VPOSR           EQU     $004
COP1LCH         EQU     $080
COP1LCL         EQU     $082
COPJMP1         EQU     $088
BPLCON0         EQU     $100
BPLCON1         EQU     $102
DIWSTRT         EQU     $08E
DIWSTOP         EQU     $090
DDFSTRT         EQU     $092
DDFSTOP         EQU     $094
BPL1MOD         EQU     $108
BPL2MOD         EQU     $10A
BPL1PTH         EQU     $0E0
BPL1PTL         EQU     $0E2
BPL2PTH         EQU     $0E4
BPL2PTL         EQU     $0E6
BPL3PTH         EQU     $0E8
BPL3PTL         EQU     $0EA
BPL4PTH         EQU     $0EC
BPL4PTL         EQU     $0EE
BPL5PTH         EQU     $0F0
BPL5PTL         EQU     $0F2
COLOR00         EQU     $180

EXEC_BASE       EQU     $4
LVO_ALLOCMEM    EQU     -198

*=============================================================================
* SCREEN SETUP
*=============================================================================

SCREEN_WIDTH    EQU     320
SCREEN_HEIGHT   EQU     256
SCREEN_PLANES   EQU     5
PLANE_SIZE      EQU     (SCREEN_WIDTH/8) * SCREEN_HEIGHT  ; 10240
SCREEN_SIZE     EQU     PLANE_SIZE * SCREEN_PLANES        ; 51200

*=============================================================================
* CODE SECTION
*=============================================================================

    SECTION VHS_CODE,CODE

*─────────────────────────────────────────────────────────────────────────────
* MAIN PROGRAM
*─────────────────────────────────────────────────────────────────────────────

Main:
    bsr     InitScreen
    bsr     InitVHS
    bsr     MainLoop
    bsr     Cleanup
    rts

*─────────────────────────────────────────────────────────────────────────────
* InitScreen — allocate and initialize screen with colored bars
*─────────────────────────────────────────────────────────────────────────────

InitScreen:
    movem.l d0-d7/a0-a6,-(sp)

    ; Allocate screen memory
    move.l  EXEC_BASE,a6
    move.l  #SCREEN_SIZE,d0
    move.l  #$10001,d1              ; MEMF_CHIP | MEMF_CLEAR
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    lea     ScreenBuf,a0
    move.l  d0,(a0)

    ; Fill screen bitplane by bitplane
    ; Color 7 (yellow) = binary 00111, so fill planes 0-2 with 1s, planes 3-4 with 0s
    move.l  d0,a0
    move.l  #PLANE_SIZE/4-1,d0
    move.l  #$FFFFFFFF,d1

    ; Fill planes 0-2 with $FFFFFFFF (yellow)
.fill_planes_0_1_2:
    move.l  d1,(a0)+
    dbra    d0,.fill_planes_0_1_2

    ; Fill planes 3-4 with $00000000 (clear)
    move.l  #PLANE_SIZE/4-1,d0
    moveq   #0,d1
.fill_planes_3_4:
    move.l  d1,(a0)+
    dbra    d0,.fill_planes_3_4

    ; Build copper list with colored bars palette
    bsr     BuildCopperList

    ; Install copper list
    lea     CopperList,a0
    move.l  a0,d0
    swap    d0
    move.w  d0,CUSTOM+COP1LCH
    swap    d0
    move.w  d0,CUSTOM+COP1LCL
    move.w  #0,CUSTOM+COPJMP1

    ; Enable display
    move.w  #$C000,CUSTOM+DMACON

.fail:
    movem.l (sp)+,d0-d7/a0-a6
    rts

*─────────────────────────────────────────────────────────────────────────────
* BuildCopperList — create copper list pointing to screen buffer
*─────────────────────────────────────────────────────────────────────────────

BuildCopperList:
    movem.l d0-d7/a0-a1,-(sp)

    lea     CopperList,a0
    lea     ScreenBuf,a1
    move.l  (a1),a1                 ; get allocated screen pointer

    ; Display window
    move.w  #DIWSTRT,(a0)+
    move.w  #$2C81,(a0)+            ; standard PAL
    move.w  #DIWSTOP,(a0)+
    move.w  #$2CC1,(a0)+
    move.w  #DDFSTRT,(a0)+
    move.w  #$0038,(a0)+
    move.w  #DDFSTOP,(a0)+
    move.w  #$00D0,(a0)+

    ; Bitplane control
    move.w  #BPLCON0,(a0)+
    move.w  #$5200,(a0)+            ; 5 planes, color on
    move.w  #BPLCON1,(a0)+
    move.w  #$0000,(a0)+
    move.w  #BPL1MOD,(a0)+
    move.w  #$0000,(a0)+
    move.w  #BPL2MOD,(a0)+
    move.w  #$0000,(a0)+

    ; Palette (8 colors for colored bars)
    move.w  #COLOR00,(a0)+
    move.w  #$0000,(a0)+            ; black
    move.w  #COLOR00+2,(a0)+
    move.w  #$0FFF,(a0)+            ; white
    move.w  #COLOR00+4,(a0)+
    move.w  #$0F00,(a0)+            ; red
    move.w  #COLOR00+6,(a0)+
    move.w  #$00F0,(a0)+            ; green
    move.w  #COLOR00+8,(a0)+
    move.w  #$000F,(a0)+            ; blue
    move.w  #COLOR00+10,(a0)+
    move.w  #$0FF0,(a0)+            ; cyan
    move.w  #COLOR00+12,(a0)+
    move.w  #$0F0F,(a0)+            ; magenta
    move.w  #COLOR00+14,(a0)+
    move.w  #$00FF,(a0)+            ; yellow

    ; Bitplane pointers
    move.w  #BPL1PTH,(a0)+
    move.l  a1,d0
    swap    d0
    move.w  d0,(a0)+
    move.w  #BPL1PTL,(a0)+
    swap    d0
    move.w  d0,(a0)+
    add.l   #PLANE_SIZE,a1

    move.w  #BPL2PTH,(a0)+
    move.l  a1,d0
    swap    d0
    move.w  d0,(a0)+
    move.w  #BPL2PTL,(a0)+
    swap    d0
    move.w  d0,(a0)+
    add.l   #PLANE_SIZE,a1

    move.w  #BPL3PTH,(a0)+
    move.l  a1,d0
    swap    d0
    move.w  d0,(a0)+
    move.w  #BPL3PTL,(a0)+
    swap    d0
    move.w  d0,(a0)+
    add.l   #PLANE_SIZE,a1

    move.w  #BPL4PTH,(a0)+
    move.l  a1,d0
    swap    d0
    move.w  d0,(a0)+
    move.w  #BPL4PTL,(a0)+
    swap    d0
    move.w  d0,(a0)+
    add.l   #PLANE_SIZE,a1

    move.w  #BPL5PTH,(a0)+
    move.l  a1,d0
    swap    d0
    move.w  d0,(a0)+
    move.w  #BPL5PTL,(a0)+
    swap    d0
    move.w  d0,(a0)+

    ; End marker
    move.w  #$FFFF,(a0)+
    move.w  #$FFFE,(a0)+

    movem.l (sp)+,d0-d7/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* InitVHS — initialize VHS effect module
*─────────────────────────────────────────────────────────────────────────────

InitVHS:
    movem.l a0,-(sp)
    lea     CopperList,a0
    jsr     VHS_NewInit
    movem.l (sp)+,a0
    rts

*─────────────────────────────────────────────────────────────────────────────
* MainLoop — simple event loop
*─────────────────────────────────────────────────────────────────────────────

MainLoop:
    movem.l d0-d7/a0-a6,-(sp)

    ; Trigger the effect (in a real app, tie this to your input system)
    jsr     VHS_NewStartEffect

.loop:
    ; Call VHS DoFrame every frame
    jsr     VHS_NewDoFrame

    ; Keep looping while effect runs, then continue after it stops
    bra     .loop

    movem.l (sp)+,d0-d7/a0-a6
    rts

*─────────────────────────────────────────────────────────────────────────────
* Cleanup — free allocated memory
*─────────────────────────────────────────────────────────────────────────────

Cleanup:
    movem.l d0-d1/a0-a1/a6,-(sp)

    lea     ScreenBuf,a0
    move.l  (a0),d0
    tst.l   d0
    beq     .no_free
    move.l  EXEC_BASE,a6
    move.l  d0,a1
    move.l  #SCREEN_SIZE,d0
    jsr     LVO_ALLOCMEM-390(a6)    ; FreeMem = LVO_ALLOCMEM - 390

.no_free:
    movem.l (sp)+,d0-d1/a0-a1/a6
    rts

*=============================================================================
* DATA SECTION
*=============================================================================

    SECTION VHS_DATA,DATA

ScreenBuf:      DS.L    1           ; screen buffer pointer
CopperList:     DS.W    512         ; copper list (2KB buffer)

*=============================================================================
* INCLUDE VHS_NEW MODULE
*=============================================================================

    INCLUDE "VHS_NEW.s"

*=============================================================================
* END
*=============================================================================

    END Main
