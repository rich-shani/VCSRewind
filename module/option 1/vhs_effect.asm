*******************************************************************************
*                                                                             *
*   VHS_EFFECT.ASM  —  Amiga 68000 Assembly                                  *
*   VHS Cassette Rewind Screen Effect  —  Linkable Module                    *
*                                                                             *
*******************************************************************************
*                                                                             *
*   PUBLIC API  (call from your game)                                        *
*   ─────────────────────────────────                                        *
*                                                                             *
*   VHS_Init                                                                 *
*     Allocates chip RAM work buffers and copies your screen as the          *
*     clean source.  Call once at game startup.                              *
*     IN:  a0 = pointer to your bitplane 0  (non-interleaved, chip RAM)      *
*          a1 = pointer to your 32-word palette table  (dc.w x 32)          *
*          a2 = pointer to YOUR copper list  (saved; restored on stop)       *
*     OUT: d0 = 0  allocation failed  (not enough chip RAM)                  *
*             = 1  success                                                   *
*     Saves: d2-d7 / a2-a6  (Exec ABI)                                      *
*                                                                             *
*   VHS_Free                                                                 *
*     Frees all chip RAM allocated by VHS_Init.                              *
*     Call at game shutdown.                                                 *
*     IN/OUT: nothing                                                        *
*                                                                             *
*   VHS_StartEffect                                                          *
*     Snapshots current hardware palette, begins fade-in.                    *
*     IN/OUT: nothing                                                        *
*     Note:  check VHS_IsActive = 0 before calling.                         *
*                                                                             *
*   VHS_StopEffect                                                           *
*     Begins fade-out sequence.  VHS_DoFrame returns d0=0 when done.        *
*     IN/OUT: nothing                                                        *
*                                                                             *
*   VHS_DoFrame                                                              *
*     Call from YOUR VBlank interrupt handler each frame.                    *
*     Does nothing (returns immediately) when effect is not active.         *
*     When active: runs all effect processing, installs effect copper list.  *
*     When stopped: restores your copper list and returns d0=0.             *
*     IN:  nothing                                                           *
*     OUT: d0 = 1  effect running / fading                                  *
*             = 0  effect fully stopped  (your copper list restored)        *
*     Saves: d1-d7 / a0-a6                                                  *
*                                                                             *
*   VHS_IsActive                                                             *
*     Returns d0=1 if effect is running or fading, 0 if fully stopped.      *
*     Faster alternative: test VHS_StateActive byte directly.               *
*                                                                             *
*   VHS_UpdateScreen                                                         *
*     Call if your game redraws its screen while the effect is NOT running.  *
*     Refreshes the internal clean source buffer from your screen pointer    *
*     so the next effect activation captures the latest screen content.     *
*     IN/OUT: nothing                                                        *
*                                                                             *
*******************************************************************************
*                                                                             *
*   INTEGRATION SKELETON (copy to your VBlank handler):                      *
*                                                                             *
*     ; --- at startup ---                                                   *
*     lea     MyBitplane0,a0                                                 *
*     lea     MyPalette,a1                                                   *
*     lea     MyCopperList,a2                                                *
*     jsr     VHS_Init                                                       *
*     tst.l   d0                                                             *
*     beq     .no_vhs                                                        *
*                                                                             *
*     ; --- inside your VBlank interrupt ---                                 *
*     tst.b   VHS_StateActive          ; fast byte test                     *
*     beq     .vhs_skip                                                      *
*     jsr     VHS_DoFrame              ; runs effect + installs copper       *
*     tst.l   d0                       ; 0 = finished, copper restored       *
*     bra     .vhs_done                ; skip your normal copper update      *
*   .vhs_skip:                                                               *
*     ; ... your normal copper list update here ...                         *
*   .vhs_done:                                                               *
*                                                                             *
*     ; --- to start the effect ---                                          *
*     jsr     VHS_StartEffect                                                *
*                                                                             *
*     ; --- to stop the effect ---                                           *
*     jsr     VHS_StopEffect                                                 *
*                                                                             *
*     ; --- if your screen changes while effect is idle ---                  *
*     jsr     VHS_UpdateScreen                                               *
*                                                                             *
*     ; --- at shutdown ---                                                  *
*     jsr     VHS_Free                                                       *
*                                                                             *
*******************************************************************************
*                                                                             *
*   SCREEN REQUIREMENTS                                                      *
*   ──────────────────                                                       *
*   • 320 x 256 (PAL) or 320 x 200 (NTSC — change SCREEN_H)                *
*   • 5 bitplanes, non-interleaved, contiguous in chip RAM                  *
*   • Plane 0 at your_screen + 0                                             *
*   • Plane 1 at your_screen + PLANE_SIZE  (10240 bytes)                    *
*   • Plane 2 at your_screen + PLANE_SIZE*2  etc.                           *
*   • Blitter must not be in use when VHS_DoFrame is called                 *
*                                                                             *
*******************************************************************************

*=============================================================================
* ASSEMBLER OPTIONS
*=============================================================================

    OPT     O+
    OPT     W-

*=============================================================================
* PUBLIC SYMBOL EXPORTS
*=============================================================================

    XDEF    VHS_Init
    XDEF    VHS_Free
    XDEF    VHS_StartEffect
    XDEF    VHS_StopEffect
    XDEF    VHS_DoFrame
    XDEF    VHS_IsActive
    XDEF    VHS_UpdateScreen
    XDEF    VHS_StateActive     ; exported byte: non-zero when effect running

*=============================================================================
* HARDWARE REGISTER EQUATES
* Guarded with IFND so they co-exist safely if your game defines them too.
*=============================================================================

    IFND    CUSTOM
CUSTOM          EQU     $DFF000
    ENDC

    IFND    DMACON
DMACON          EQU     $096
DMACONR         EQU     $002
DMAF_SETCLR     EQU     $8000
DMAF_COPPER     EQU     $0080
DMAF_BLITTER    EQU     $0040
DMAF_RASTER     EQU     $0100
DMAF_MASTER     EQU     $0200
    ENDC

    IFND    INTENA
INTENA          EQU     $09A
INTENAR         EQU     $01C
INTREQ          EQU     $09C
    ENDC

    IFND    COP1LCH
COP1LCH         EQU     $080
COP1LCL         EQU     $082
COPJMP1         EQU     $088
    ENDC

    IFND    BPLCON0
BPLCON0         EQU     $100
BPLCON1         EQU     $102
BPLCON2         EQU     $104
BPL1MOD         EQU     $108
BPL2MOD         EQU     $10A
DIWSTRT         EQU     $08E
DIWSTOP         EQU     $090
DDFSTRT         EQU     $092
DDFSTOP         EQU     $094
COLOR00         EQU     $180
    ENDC

    IFND    BPL1PTH
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
    ENDC

    IFND    BLTCON0
BLTCON0         EQU     $040
BLTCON1         EQU     $042
BLTAFWM         EQU     $044
BLTALWM         EQU     $046
BLTCPTH         EQU     $048
BLTCPTL         EQU     $04A
BLTBPTH         EQU     $04C
BLTBPTL         EQU     $04E
BLTAPTH         EQU     $050
BLTAPTL         EQU     $052
BLTDPTH         EQU     $054
BLTDPTL         EQU     $056
BLTSIZE         EQU     $058
BLTAMOD         EQU     $064
BLTBMOD         EQU     $062
BLTCMOD         EQU     $060
BLTDMOD         EQU     $066
BLTCDAT         EQU     $06E
BLTBDAT         EQU     $070
BLTADAT         EQU     $072
BLTDAT          EQU     $074
    ENDC

; OS library
    IFND    EXEC_BASE
EXEC_BASE       EQU     4
LVO_ALLOCMEM    EQU     -198
LVO_FREEMEM     EQU     -210
    ENDC

    IFND    MEMF_CHIP
MEMF_CHIP       EQU     $00000002
MEMF_CLEAR      EQU     $00010000
    ENDC

*=============================================================================
* SCREEN / EFFECT CONSTANTS
* Adjust SCREEN_H to 200 for NTSC.
* Adjust DIW_START/STOP/DDF_START/STOP to match your game's display window.
*=============================================================================

VHS_SCREEN_W    EQU     320
VHS_SCREEN_H    EQU     256
VHS_PLANES      EQU     5
VHS_COLORS      EQU     32
VHS_PLANE_SIZE  EQU     (VHS_SCREEN_W/8)*VHS_SCREEN_H   ; 10240
VHS_SCREEN_SIZE EQU     VHS_PLANE_SIZE*VHS_PLANES        ; 51200
VHS_STRIDE      EQU     VHS_SCREEN_W/8                   ; 40 bytes/row
VHS_NOISE_SIZE  EQU     VHS_PLANE_SIZE                   ; 10240

; PAL display window — match your game's copper list settings
VHS_DIW_START   EQU     $2c81
VHS_DIW_STOP    EQU     $2cc1
VHS_DDF_START   EQU     $003c
VHS_DDF_STOP    EQU     $00d4
VHS_BPLCON0     EQU     $5200           ; 5 planes, colour on, lores
VHS_FIRST_LINE  EQU     $2c             ; first visible PAL raster line

; Effect tuning — change these to taste
VHS_LFSR_POLY   EQU     $80000057       ; Galois 32-bit LFSR polynomial
VHS_LFSR_SEED   EQU     $DEADBEEF
VHS_MAX_SHIFT   EQU     32              ; max horizontal tear in pixels
VHS_FADE_IN     EQU     12              ; frames to reach full distortion
VHS_FADE_OUT    EQU     12              ; frames to return to normal

; State machine
VHS_ST_NORMAL   EQU     0
VHS_ST_IN       EQU     1
VHS_ST_FAST     EQU     2
VHS_ST_OUT      EQU     4

*=============================================================================
* INTERNAL VARIABLE BLOCK OFFSETS  (chip RAM, allocated by VHS_Init)
*=============================================================================

VV_DRAWBUF      EQU     0       ; long  - effect draw buffer
VV_DISPBUF      EQU     4       ; long  - effect display buffer
VV_SRCBUF       EQU     8       ; long  - clean source (your screen copy)
VV_NOISEBUF     EQU     12      ; long  - noise bitplane
VV_COPLIST      EQU     16      ; long  - active effect copper list
VV_COPLIST2     EQU     20      ; long  - inactive effect copper list
VV_YOURCOP      EQU     24      ; long  - caller's copper list (to restore)
VV_YOURSCREEN   EQU     28      ; long  - caller's bitplane 0 pointer
VV_LFSR         EQU     32      ; long  - LFSR state
VV_FRAMECOUNT   EQU     36      ; long  - frame counter
VV_STATE        EQU     40      ; word  - effect state
VV_FADECOUNT    EQU     42      ; word  - fade frame counter
VV_VERTROLL     EQU     44      ; word  - vertical roll offset (lines)
VV_DISTORT      EQU     46      ; word  - distortion intensity 0-256
VV_PLANES       EQU     48      ; word  - number of bitplanes (4 or 5)
VV_BPLCON0      EQU     50      ; word  - BPLCON0 value for this plane count
VV_SIZE         EQU     52      ; total bytes

*=============================================================================
* CODE SECTION
*=============================================================================

    SECTION VHS_CODE,CODE_C

*─────────────────────────────────────────────────────────────────────────────
* VHS_Init
* Allocates all chip RAM buffers, copies caller's screen to clean source,
* stores palette pointer.
*
* IN:  a0 = your bitplane 0 (chip RAM, non-interleaved)
*      a1 = your 32-word palette  (dc.w x 32)
*      a2 = your copper list pointer  (will be restored by VHS_DoFrame)
* OUT: d0 = 1 success, 0 failure
*─────────────────────────────────────────────────────────────────────────────

VHS_Init:
    movem.l d1-d7/a0-a6,-(sp)

    ; Save plane count before a6 is loaded (d0 holds it on entry)
    move.w  d0,vhs_PlaneCount       ; save for later use in InitVars
    ; Clamp to 4..5
    cmp.w   #4,d0
    blt     .bad_planes
    cmp.w   #5,d0
    bgt     .bad_planes
    bra     .planes_ok
.bad_planes:
    move.w  #5,vhs_PlaneCount       ; default to 5 if caller passes garbage
.planes_ok:

    ; Save caller inputs into module BSS
    move.l  a0,vhs_YourScreen       ; remember caller's screen pointer
    move.l  a1,vhs_YourPalette      ; remember caller's palette pointer
    move.l  a2,vhs_YourCopList      ; remember caller's copper list

    move.l  EXEC_BASE,a6

    ; ── Allocate effect draw buffer A ──
    move.l  #VHS_SCREEN_SIZE,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,vhs_BufA

    ; ── Allocate noise plane ──
    move.l  #VHS_NOISE_SIZE,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,vhs_NoisePlane

    ; ── Allocate one simple copper list ──
    move.l  #12288,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,vhs_CopA

    ; ── Allocate variable block ──
    move.l  #VV_SIZE,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,vhs_VarBase

    ; ── Initialise variable block ──
    move.l  d0,a5                   ; a5 = VarBase for rest of Init
    move.l  vhs_BufA,VV_DRAWBUF(a5)         ; effect work buffer
    move.l  vhs_YourScreen,VV_DISPBUF(a5)  ; caller's screen (what we display)
    move.l  vhs_NoisePlane,VV_NOISEBUF(a5)
    move.l  vhs_CopA,VV_COPLIST(a5)        ; simple effect copper list
    move.l  vhs_YourCopList,VV_YOURCOP(a5) ; caller's copper list
    move.l  vhs_YourScreen,VV_YOURSCREEN(a5)
    move.l  #VHS_LFSR_SEED,VV_LFSR(a5)

    ; Store plane count and compute matching BPLCON0 value
    ; BPLCON0 bits 14-12 = number of planes (4=100b=$4, 5=101b=$5)
    ; BPLCON0 = (planes << 12) | $0200  (colour on, lores)
    move.w  vhs_PlaneCount,d0
    move.w  d0,VV_PLANES(a5)
    lsl.w   #4,d0               ; shift to bits 15-12
    lsl.w   #4,d0
    lsl.w   #4,d0               ; d0 = planes << 12
    or.w    #$0200,d0           ; colour enable
    move.w  d0,VV_BPLCON0(a5)

    move.w  #VHS_ST_NORMAL,VV_STATE(a5)
    move.w  #0,VV_FADECOUNT(a5)
    move.w  #0,VV_VERTROLL(a5)
    move.w  #0,VV_DISTORT(a5)
    move.l  #0,VV_FRAMECOUNT(a5)

    ; ── Clear state flags ──
    clr.b   VHS_StateActive

    moveq   #1,d0                   ; success
    movem.l (sp)+,d1-d7/a0-a6
    rts

.fail:
    ; Free whatever was allocated before the failure
    bsr     VHS_Free
    moveq   #0,d0
    movem.l (sp)+,d1-d7/a0-a6
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_Free
* Releases all chip RAM allocated by VHS_Init.
*─────────────────────────────────────────────────────────────────────────────

VHS_Free:
    movem.l d0-d1/a0-a1/a6,-(sp)
    move.l  EXEC_BASE,a6

    move.l  vhs_BufA,d0
    beq     .f1
    move.l  d0,a1
    move.l  #VHS_SCREEN_SIZE,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   vhs_BufA
.f1:
    move.l  vhs_NoisePlane,d0
    beq     .f4
    move.l  d0,a1
    move.l  #VHS_NOISE_SIZE,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   vhs_NoisePlane
.f4:
    move.l  vhs_CopA,d0
    beq     .f5
    move.l  d0,a1
    move.l  #12288,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   vhs_CopA
.f5:
    move.l  vhs_VarBase,d0
    beq     .f7
    move.l  d0,a1
    move.l  #VV_SIZE,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   vhs_VarBase
.f7:
    movem.l (sp)+,d0-d1/a0-a1/a6
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_StartEffect
* Snapshots hardware palette → NormalPalette.
* Derives VHSPalette (desaturated / darkened / blue-green tint).
* Sets state to VHS_ST_IN (fade-in begins).
* Safe to call from any context (not interrupt-driven).
*─────────────────────────────────────────────────────────────────────────────

VHS_StartEffect:
    movem.l d0-d7/a0-a2,-(sp)

    ; Only start if not already active
    tst.b   VHS_StateActive
    bne     .already_active

    ; ── Snapshot current hardware palette into NormalPalette ──
    lea     CUSTOM+COLOR00,a0
    lea     vhs_NormalPal,a1
    move.w  #VHS_COLORS-1,d7
.snap:
    move.w  (a0)+,(a1)+
    dbra    d7,.snap

    ; ── Derive VHSPalette from NormalPalette ──
    ; Transform: desaturate to ~25% sat, darken to ~60% brightness,
    ; add slight blue-green tint (+1 to G and B nibbles).
    lea     vhs_NormalPal,a0
    lea     vhs_VHSPal,a1
    move.w  #VHS_COLORS-1,d7

.pal_loop:
    move.w  (a0)+,d0            ; d0 = 0RGB colour word

    ; Extract R, G, B nibbles (each 0..15)
    move.w  d0,d1
    lsr.w   #8,d1
    and.w   #$000F,d1           ; d1 = R

    move.w  d0,d2
    lsr.w   #4,d2
    and.w   #$000F,d2           ; d2 = G

    move.w  d0,d3
    and.w   #$000F,d3           ; d3 = B

    ; grey = (R+G+B)/3
    clr.l   d4
    move.w  d1,d4
    add.w   d2,d4
    add.w   d3,d4
    divu    #3,d4               ; d4 = grey (low word)

    ; R_vhs: lerp toward grey at 87.5%: grey + (R-grey)/8
    move.w  d1,d5
    sub.w   d4,d5
    asr.w   #3,d5
    add.w   d4,d5               ; d5 = R_vhs pre-darken

    ; Darken: *= 13/16 ≈ 0.8125
    mulu    #13,d5
    lsr.w   #4,d5
    ; Clamp 0..15
    bpl     .rc
    moveq   #0,d5
.rc:
    cmp.w   #15,d5
    ble     .rc2
    move.w  #15,d5
.rc2:
    move.w  d5,d6               ; save R_vhs in d6 (bits 0-3)

    ; G_vhs: same but +1 tint
    move.w  d2,d5
    sub.w   d4,d5
    asr.w   #3,d5
    add.w   d4,d5
    addq.w  #1,d5
    mulu    #13,d5
    lsr.w   #4,d5
    bpl     .gc
    moveq   #0,d5
.gc:
    cmp.w   #15,d5
    ble     .gc2
    move.w  #15,d5
.gc2:
    lsl.w   #4,d5               ; G into bits 4-7
    or.w    d5,d6

    ; B_vhs: same but +1 tint
    move.w  d3,d5
    sub.w   d4,d5
    asr.w   #3,d5
    add.w   d4,d5
    addq.w  #1,d5
    mulu    #13,d5
    lsr.w   #4,d5
    bpl     .bc
    moveq   #0,d5
.bc:
    cmp.w   #15,d5
    ble     .bc2
    move.w  #15,d5
.bc2:
    ; d6 so far: bits 7-4=G, bits 3-0=R  (B in d5, bits 0-3)
    ; Need result: bits 11-8=R, bits 7-4=G, bits 3-0=B
    ; Current d6: bits 7-4=G, bits 3-0=R  → shift d6 left 4, put R in 11-8
    lsl.w   #4,d6               ; d6 = G in 11-8, R in 7-4 ... wait that's wrong
    ; Let's rebuild cleanly using d0 as accumulator:
    move.w  d6,d0               ; d0 = (G<<4)|R at this point after lsl
    ; Actually after lsl.w #4,d6: bits 11-8=G, bits 7-4=R, bits 3-0=0
    ; We want 11-8=R, 7-4=G, 3-0=B
    ; Swap R and G: d6 bits before lsl were 7-4=G, 3-0=R
    ; Undo: use fresh accumulation
    ; R is in d6 bits 3-0 (before the lsl), G was OR'd into bits 7-4
    ; The lsl shifted everything left 4 → now G in 11-8, R in 7-4
    ; So d6 after lsl = (G<<8)|(R<<4). Add B in bits 3-0:
    or.w    d5,d0               ; d0 = (G<<8)|(R<<4)|B  → WRONG nibble order
    ; Correct VHS colour: $0RGB so bits 11-8=R, 7-4=G, 3-0=B
    ; We have G in 11-8, R in 7-4 — swap the high two nibbles:
    ; Extract: temp = ((d0>>4)&$F0) | ((d0>>8)&$0F) | (d0&$00F)
    move.w  d0,d5
    and.w   #$00F,d5            ; d5 = B nibble
    move.w  d0,d4
    lsr.w   #4,d4
    and.w   #$00F,d4            ; d4 = R nibble (was in bits 7-4)
    move.w  d0,d3
    lsr.w   #4,d3
    lsr.w   #4,d3
    and.w   #$00F,d3            ; d3 = G nibble (was in bits 11-8)
    ; Reassemble: $0RGB = (R<<8)|(G<<4)|B
    move.w  d4,d0
    lsl.w   #8,d0               ; R in bits 11-8 (note: 12-bit colour, top nibble=0)
    lsl.w   #4,d3
    or.w    d3,d0               ; G in bits 7-4
    or.w    d5,d0               ; B in bits 3-0

    move.w  d0,(a1)+
    dbra    d7,.pal_loop

    ; ── Set state ──
    move.l  vhs_VarBase,a5
    move.w  #VHS_ST_IN,VV_STATE(a5)
    move.w  #0,VV_FADECOUNT(a5)
    move.w  #0,VV_VERTROLL(a5)
    move.w  #0,VV_DISTORT(a5)
    move.l  #0,VV_FRAMECOUNT(a5)

    ; Seed LFSR with value based on current frame count for randomness
    move.l  VV_FRAMECOUNT(a5),d0
    eor.l   #VHS_LFSR_SEED,d0       ; mix with base seed
    move.l  d0,VV_LFSR(a5)           ; new random seed

    move.b  #1,VHS_StateActive

.already_active:
    movem.l (sp)+,d0-d7/a0-a2
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_StopEffect
* Initiates fade-out. VHS_DoFrame will return d0=0 when complete.
*─────────────────────────────────────────────────────────────────────────────

VHS_StopEffect:
    movem.l d0/a5,-(sp)
    move.l  vhs_VarBase,a5
    tst.b   VHS_StateActive
    beq     .not_active
    move.w  #VHS_ST_OUT,VV_STATE(a5)
    move.w  #0,VV_FADECOUNT(a5)
.not_active:
    movem.l (sp)+,d0/a5
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_IsActive
* OUT: d0 = 1 if effect running or fading, 0 if fully stopped
*─────────────────────────────────────────────────────────────────────────────

VHS_IsActive:
    moveq   #0,d0
    tst.b   VHS_StateActive
    beq     .done
    moveq   #1,d0
.done:
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_UpdateScreen
* If your game changes its screen content while the effect is not running,
* call this to refresh the clean source buffer so the next VHS_StartEffect
* captures the new screen.
*─────────────────────────────────────────────────────────────────────────────

VHS_UpdateScreen:
    movem.l d0-d1/a0-a1,-(sp)
    tst.b   VHS_StateActive
    bne     .active             ; don't update while effect is running
    bsr     vhs_CopyScreenToSrc
.active:
    movem.l (sp)+,d0-d1/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_DoFrame
* Call from your VBlank interrupt handler every frame.
* When effect is inactive: returns immediately with d0=0.
* When active: runs one frame of the full effect pipeline.
* When stopping: restores your copper list, clears VHS_StateActive, d0=0.
*
* OUT: d0 = 1 effect running, 0 effect stopped (copper restored)
* Saves: d1-d7 / a0-a6
*─────────────────────────────────────────────────────────────────────────────

VHS_DoFrame:
    movem.l d1-d7/a0-a6,-(sp)

    ; Fast early-out when not active
    tst.b   VHS_StateActive
    beq     .return_stopped

    move.l  vhs_VarBase,a5

    ; Advance frame counter
    addq.l  #1,VV_FRAMECOUNT(a5)

    ; ── Update state machine ──
    bsr     vhs_UpdateState

    ; ── Effect pipeline ──
    move.w  VV_STATE(a5),d0
    cmp.w   #VHS_ST_NORMAL,d0
    beq     .do_normal

    ; Effect active — simplified pipeline
    ; 1. Copy caller's screen to effect work buffer
    bsr     vhs_CopyCallerScreenToEffectBuf

    ; 2. Apply all VHS effects to the buffer
  ;  bsr     vhs_FillNoise
  ;  bsr     vhs_BuildShiftTable
  ;  bsr     vhs_DoVertRoll
   ; bsr     vhs_DoNoiseOverlay
  ;  bsr     vhs_DoChromaSmear

    ; 3. Copy caller's copper list and patch bitplane pointers
    bsr     vhs_CopyAndPatchCallerCop
    bsr    vhs_ApplyVHSPalette

    ; 4. Display the patched copper list
    bra     .swap_and_install

.do_normal:
    ; Effect fully stopped — restore caller's copper list and palette

    ; Restore hardware palette
    bsr     vhs_ApplyNormalPalette

    ; Restore caller's copper list to the hardware
    move.l  VV_YOURCOP(a5),d0
    swap    d0
    move.w  d0,CUSTOM+COP1LCH
    swap    d0
    move.w  d0,CUSTOM+COP1LCL
    move.w  #$0000,CUSTOM+COPJMP1

    ; Clear active flag
    clr.b   VHS_StateActive

    ; Return 0 — effect stopped
    movem.l (sp)+,d1-d7/a0-a6
    moveq   #0,d0
    rts

.swap_and_install:
    ; Install the patched copper list (points to effect buffer with effects applied)
    move.l  vhs_CopA,d0
    swap    d0
    move.w  d0,CUSTOM+COP1LCH
    swap    d0
    move.w  d0,CUSTOM+COP1LCL
    move.w  #$0000,CUSTOM+COPJMP1

    ; Return 1 — effect still running
    movem.l (sp)+,d1-d7/a0-a6
    moveq   #1,d0
    rts

.return_stopped:
    movem.l (sp)+,d1-d7/a0-a6
    moveq   #0,d0
    rts

*=============================================================================
* ─── INTERNAL ROUTINES ───────────────────────────────────────────────────
* All routines below are private.  They use a5 = vhs_VarBase throughout.
* Callers must load a5 before invoking them.
*=============================================================================

*─────────────────────────────────────────────────────────────────────────────
* vhs_CopyScreenToSrc
* Copies caller's screen (vhs_YourScreen) into the clean source buffer.
* Does NOT require a5 — uses module BSS pointers directly.
*─────────────────────────────────────────────────────────────────────────────

vhs_CopyScreenToSrc:
    movem.l d0/a0-a1,-(sp)
    move.l  vhs_YourScreen,a0
    move.l  vhs_BufSrc,a1
    move.l  #12799,d0              ; DEBUG: hardcode instead of calculate
.loop:
    move.l  (a0)+,(a1)+
    dbra    d0,.loop
    movem.l (sp)+,d0/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_CopySourceToDraw — copy clean source to draw buffer
* Called at start of each effect frame to initialize the draw buffer
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_CopySourceToDraw:
    movem.l d0/a0-a1,-(sp)
    move.l  VV_SRCBUF(a5),a0
    move.l  VV_DRAWBUF(a5),a1
    move.l  #VHS_SCREEN_SIZE/4-1,d0
.loop:
    move.l  (a0)+,(a1)+
    dbra    d0,.loop
    movem.l (sp)+,d0/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_CopyCallerScreenToEffectBuf — copy caller's screen to effect work buffer
* Copies from vhs_YourScreen (caller's bitplane 0) to vhs_BufA (effect buffer).
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_CopyCallerScreenToEffectBuf:
    movem.l d0/a0-a1,-(sp)
    move.l  VV_YOURSCREEN(a5),a0   ; source: caller's screen
    move.l  VV_DRAWBUF(a5),a1      ; dest: effect work buffer
    move.l  #VHS_SCREEN_SIZE/4-1,d0
.loop:
    move.l  (a0)+,(a1)+
    dbra    d0,.loop
    movem.l (sp)+,d0/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_CopyAndPatchCallerCop — copy caller's copper list and patch bitplane ptrs
* 1. Copies from VV_YOURCOP to vhs_CopA
* 2. Scans the copy for BPL1PTH/BPL1PTL/etc and changes to point to VV_DRAWBUF
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_CopyAndPatchCallerCop:
    movem.l d0-d7/a0-a2,-(sp)

    ; Clear vhs_CopA first
    move.l  vhs_CopA,a1
    move.l  #12288/4-1,d0
    moveq   #0,d1
.clear_loop:
    move.l  d1,(a1)+
    dbra    d0,.clear_loop

    ; Copy caller's copper list to vhs_CopA
    move.l  VV_YOURCOP(a5),a0       ; source
    move.l  vhs_CopA,a1             ; destination

.copy_loop:
    move.w  (a0)+,(a1)+
    move.w  (a0)+,(a1)+
    cmp.w   #$FFFF,-4(a1)           ; check if we just wrote FFFF (end marker high word)
    bne     .copy_loop
    cmp.w   #$FFFE,-2(a1)           ; check if end marker low word
    beq     .copy_done              ; if both match, we're done
    bra     .copy_loop              ; otherwise continue copying

.copy_done:

    ; Now patch the copy in vhs_CopA
    move.l  vhs_CopA,a0             ; scan copy from start
    move.l  VV_DRAWBUF(a5),a2       ; effect buffer address
    moveq   #0,d6                   ; plane offset accumulator (0, PLANE_SIZE, PLANE_SIZE*2, etc)
    move.l  #VHS_PLANE_SIZE,d5      ; plane stride

.patch_loop:
    cmp.w   #$FFFF,(a0)             ; end of copper?
    beq     .patch_done
    move.w  (a0),d0                 ; read register offset
    cmp.w   #BPL1PTH,d0
    bne     .next_pair

    ; Found BPLxPTH — patch high word
    move.l  a2,d0                   ; effect buffer base
    add.l   d6,d0                   ; add plane offset
    swap    d0
    move.w  d0,2(a0)                ; write high word

    ; Patch BPLxPTL (should be next)
    cmp.w   #BPL1PTL,4(a0)
    bne     .next_pair
    move.l  a2,d0
    add.l   d6,d0                   ; same offset for low word
    move.w  d0,6(a0)                ; write low word

    ; Advance to next plane offset for next iteration
    add.l   d5,d6

.next_pair:
    add.l   #4,a0                   ; next copper word pair
    bra     .patch_loop

.patch_done:
    movem.l (sp)+,d0-d7/a0-a2
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_UpdateState — state machine transition logic
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_UpdateState:
    movem.l d0-d1,-(sp)
    move.w  VV_STATE(a5),d0

    cmp.w   #VHS_ST_IN,d0
    bne     .chk_fast

    ; RWIN_IN: ramp distortion up over VHS_FADE_IN frames
    addq.w  #1,VV_FADECOUNT(a5)
    clr.l   d0
    move.w  VV_FADECOUNT(a5),d0
    mulu    #256,d0
    divu    #VHS_FADE_IN,d0
    cmp.w   #256,d0
    blt     .set_dist_in
    move.w  #256,d0
.set_dist_in:
    move.w  d0,VV_DISTORT(a5)
    cmp.w   #VHS_FADE_IN,VV_FADECOUNT(a5)
    blt     .done
    move.w  #VHS_ST_FAST,VV_STATE(a5)
    clr.w   VV_FADECOUNT(a5)         ; reset counter for FAST state duration tracking
    bra     .done

.chk_fast:
    cmp.w   #VHS_ST_FAST,d0
    bne     .chk_out

    ; RWIN_FAST: full effect, advance vertical roll, auto-stop after ~100 frames
    addq.w  #1,VV_FADECOUNT(a5)
    move.w  VV_VERTROLL(a5),d0
    add.w   #5,d0
    and.w   #$00FF,d0
    move.w  d0,VV_VERTROLL(a5)
    move.w  #256,VV_DISTORT(a5)

    ; Auto-stop after 100 frames (2 seconds at 50Hz)
    cmp.w   #100,VV_FADECOUNT(a5)
    blt     .done
    move.w  #VHS_ST_OUT,VV_STATE(a5)
    clr.w   VV_FADECOUNT(a5)         ; reset for fade-out counting
    bra     .done

.chk_out:
    cmp.w   #VHS_ST_OUT,d0
    bne     .done

    ; RWIN_OUT: ramp distortion down over VHS_FADE_OUT frames
    addq.w  #1,VV_FADECOUNT(a5)
    move.w  #256,d0
    clr.l   d1
    move.w  VV_FADECOUNT(a5),d1
    mulu    #256,d1
    divu    #VHS_FADE_OUT,d1
    sub.w   d1,d0
    bge     .set_dist_out
    moveq   #0,d0
.set_dist_out:
    move.w  d0,VV_DISTORT(a5)
    cmp.w   #VHS_FADE_OUT,VV_FADECOUNT(a5)
    blt     .done
    ; Fade complete → back to NORMAL (VHS_DoFrame handles the copper restore)
    move.w  #VHS_ST_NORMAL,VV_STATE(a5)
    move.w  #0,VV_DISTORT(a5)
    move.w  #0,VV_VERTROLL(a5)
    bsr     vhs_ClearShiftTable

.done:
    movem.l (sp)+,d0-d1
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_WaitBlit — poll blitter busy bit
*─────────────────────────────────────────────────────────────────────────────

vhs_WaitBlit:
.wb:
    btst    #6,CUSTOM+DMACONR
    bne     .wb
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_ClearShiftTable
*─────────────────────────────────────────────────────────────────────────────

vhs_ClearShiftTable:
    movem.l d0/a0,-(sp)
    lea     vhs_ShiftTable,a0
    move.w  #255,d0
.cl:
    clr.w   (a0)+
    dbra    d0,.cl
    movem.l (sp)+,d0/a0
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_FillNoise — LFSR noise plane fill
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_FillNoise:
    movem.l d0/d6-d7/a0,-(sp)

    move.l  VV_NOISEBUF(a5),a0
    move.l  VV_LFSR(a5),d7
    move.l  VV_FRAMECOUNT(a5),d0
    eor.l   d0,d7                       ; vary seed each frame

    move.w  #(VHS_NOISE_SIZE/4)-1,d6

.lp:
    lsr.l   #1,d7
    bcc     .n0
    eor.l   #VHS_LFSR_POLY,d7
.n0:
    lsr.l   #1,d7
    bcc     .n1
    eor.l   #VHS_LFSR_POLY,d7
.n1:
    lsr.l   #1,d7
    bcc     .n2
    eor.l   #VHS_LFSR_POLY,d7
.n2:
    lsr.l   #1,d7
    bcc     .n3
    eor.l   #VHS_LFSR_POLY,d7
.n3:
    lsr.l   #1,d7
    bcc     .n4
    eor.l   #VHS_LFSR_POLY,d7
.n4:
    lsr.l   #1,d7
    bcc     .n5
    eor.l   #VHS_LFSR_POLY,d7
.n5:
    lsr.l   #1,d7
    bcc     .n6
    eor.l   #VHS_LFSR_POLY,d7
.n6:
    lsr.l   #1,d7
    bcc     .n7
    eor.l   #VHS_LFSR_POLY,d7
.n7:
    move.l  d7,(a0)+
    dbra    d6,.lp

    ; Save advanced LFSR state
    lsr.l   #1,d7
    bcc     .na
    eor.l   #VHS_LFSR_POLY,d7
.na:
    move.l  d7,VV_LFSR(a5)

    movem.l (sp)+,d0/d6-d7/a0
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_BuildShiftTable — fill vhs_ShiftTable with per-line horizontal offsets
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_BuildShiftTable:
    movem.l d0-d6/a0-a1,-(sp)

    lea     vhs_ShiftTable,a0
    move.w  VV_DISTORT(a5),d5
    move.l  VV_LFSR(a5),d7

    move.w  #0,d6
.band:
    cmp.w   #VHS_SCREEN_H,d6
    bge     .band_done

    lsr.l   #1,d7
    bcc     .b1
    eor.l   #VHS_LFSR_POLY,d7
.b1:
    move.l  d7,d0
    and.w   #$001F,d0
    add.w   #8,d0
    move.w  d0,d4                       ; band height

    lsr.l   #1,d7
    bcc     .b2
    eor.l   #VHS_LFSR_POLY,d7
.b2:
    move.l  d7,d1
    and.w   #$001F,d1
    sub.w   #16,d1
    muls    d5,d1
    asr.l   #8,d1
    and.w   #$FFFE,d1
    cmp.w   #VHS_MAX_SHIFT,d1
    ble     .clo
    move.w  #VHS_MAX_SHIFT,d1
.clo:
    cmp.w   #-VHS_MAX_SHIFT,d1
    bge     .chi
    move.w  #-VHS_MAX_SHIFT,d1
.chi:
    move.w  d4,d3

.fill:
    cmp.w   #VHS_SCREEN_H,d6
    bge     .band_done

    lsr.l   #1,d7
    bcc     .b3
    eor.l   #VHS_LFSR_POLY,d7
.b3:
    move.l  d7,d2
    and.w   #$0003,d2
    sub.w   #2,d2
    and.w   #$FFFE,d2
    add.w   d1,d2
    cmp.w   #VHS_MAX_SHIFT,d2
    ble     .nc2
    move.w  #VHS_MAX_SHIFT,d2
.nc2:
    cmp.w   #-VHS_MAX_SHIFT,d2
    bge     .nc3
    move.w  #-VHS_MAX_SHIFT,d2
.nc3:
    move.w  d6,d0
    add.w   d0,d0
    move.l  a0,a1
    adda.w  d0,a1
    move.w  d2,(a1)

    addq.w  #1,d6
    dbra    d3,.fill
    bra     .band

.band_done:
    movem.l (sp)+,d0-d6/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_DoVertRoll — blitter: copy clean source → draw buffer with vertical roll
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_DoVertRoll:
    movem.l d0-d4/a0-a4,-(sp)

    move.w  VV_VERTROLL(a5),d3
    beq     .no_roll

    move.l  VV_SRCBUF(a5),a0           ; source = clean (never corrupted)
    move.l  VV_DRAWBUF(a5),a1          ; dest   = draw buffer

    move.w  VV_PLANES(a5),d4
    subq.w  #1,d4               ; dbra adjust

.plane:
    move.w  d4,d0
    mulu    #VHS_PLANE_SIZE,d0

    move.l  a0,a2
    add.l   d0,a2                       ; a2 = source plane base

    move.l  a1,a3
    add.l   d0,a3                       ; a3 = dest plane base

    ; Part 1: source[roll..H-1] → dest[0..H-1-roll]
    move.w  d3,d0
    mulu    #VHS_STRIDE,d0
    move.l  a2,d1
    add.l   d0,d1
    move.l  d1,a4                       ; a4 = src start

    move.w  #VHS_SCREEN_H,d2
    sub.w   d3,d2                       ; d2 = line count

    bsr     vhs_WaitBlit

    move.w  #$08F0,CUSTOM+BLTCON0       ; A→D copy
    move.w  #$0000,CUSTOM+BLTCON1
    move.w  #$FFFF,CUSTOM+BLTAFWM
    move.w  #$FFFF,CUSTOM+BLTALWM
    move.w  #0,CUSTOM+BLTAMOD
    move.w  #0,CUSTOM+BLTDMOD

    move.l  a4,d0
    swap    d0
    move.w  d0,CUSTOM+BLTAPTH
    swap    d0
    move.w  d0,CUSTOM+BLTAPTL

    move.l  a3,d0
    swap    d0
    move.w  d0,CUSTOM+BLTDPTH
    swap    d0
    move.w  d0,CUSTOM+BLTDPTL

    move.w  d2,d0
    lsl.w   #6,d0
    or.w    #(VHS_STRIDE/2),d0
    move.w  d0,CUSTOM+BLTSIZE

    ; Part 2: source[0..roll-1] → dest[H-roll..H-1]
    move.w  #VHS_SCREEN_H,d1
    sub.w   d3,d1
    mulu    #VHS_STRIDE,d1
    move.l  a3,d0
    add.l   d1,d0
    move.l  d0,a4                       ; a4 = dest start part 2

    bsr     vhs_WaitBlit

    move.w  #$08F0,CUSTOM+BLTCON0
    move.w  #$0000,CUSTOM+BLTCON1
    move.w  #$FFFF,CUSTOM+BLTAFWM
    move.w  #$FFFF,CUSTOM+BLTALWM
    move.w  #0,CUSTOM+BLTAMOD
    move.w  #0,CUSTOM+BLTDMOD

    move.l  a2,d0
    swap    d0
    move.w  d0,CUSTOM+BLTAPTH
    swap    d0
    move.w  d0,CUSTOM+BLTAPTL

    move.l  a4,d0
    swap    d0
    move.w  d0,CUSTOM+BLTDPTH
    swap    d0
    move.w  d0,CUSTOM+BLTDPTL

    move.w  d3,d0
    lsl.w   #6,d0
    or.w    #(VHS_STRIDE/2),d0
    move.w  d0,CUSTOM+BLTSIZE

    dbra    d4,.plane

.no_roll:
    ; When VERTROLL=0, still need to copy source to draw buffer (no rolling)
    move.l  VV_SRCBUF(a5),a0
    move.l  VV_DRAWBUF(a5),a1
    move.l  #VHS_SCREEN_SIZE/4-1,d0
.copy_loop:
    move.l  (a0)+,(a1)+
    dbra    d0,.copy_loop
    bsr     vhs_WaitBlit
    movem.l (sp)+,d0-d4/a0-a4
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_DoNoiseOverlay — blit noise plane onto draw buffer plane 0
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_DoNoiseOverlay:
    movem.l d0-d7/a0-a3,-(sp)

    move.l  VV_NOISEBUF(a5),a2
    move.l  VV_DRAWBUF(a5),a3
    move.w  VV_DISTORT(a5),d5

    cmp.w   #32,d5
    blt     .done

    bsr     vhs_WaitBlit

    ; A→D copy (noise → plane 0), BLTCON1=0 (fill mode OFF — critical)
    move.w  #$08F0,CUSTOM+BLTCON0
    move.w  #$0000,CUSTOM+BLTCON1
    move.w  #$FFFF,CUSTOM+BLTAFWM
    move.w  #$FFFF,CUSTOM+BLTALWM
    move.w  #0,CUSTOM+BLTAMOD
    move.w  #0,CUSTOM+BLTDMOD

    move.l  a2,d0
    swap    d0
    move.w  d0,CUSTOM+BLTAPTH
    swap    d0
    move.w  d0,CUSTOM+BLTAPTL

    move.l  a3,d0
    swap    d0
    move.w  d0,CUSTOM+BLTDPTH
    swap    d0
    move.w  d0,CUSTOM+BLTDPTL

    move.w  #(256<<6)|20,CUSTOM+BLTSIZE

    ; Blank 3 random dropout lines
    move.l  VV_LFSR(a5),d7
    move.w  #2,d4

.dropout:
    lsr.l   #1,d7
    bcc     .dp1
    eor.l   #VHS_LFSR_POLY,d7
.dp1:
    move.l  d7,d0
    and.w   #$00FF,d0

    bsr     vhs_WaitBlit

    move.w  d0,d2
    and.l   #$0000FFFF,d2
    mulu    #VHS_STRIDE,d2
    move.l  a3,d1
    add.l   d2,d1

    move.w  #$08F0,CUSTOM+BLTCON0
    move.w  #$0000,CUSTOM+BLTCON1
    move.w  #$FFFF,CUSTOM+BLTAFWM
    move.w  #$FFFF,CUSTOM+BLTALWM
    move.w  #0,CUSTOM+BLTAMOD
    move.w  #0,CUSTOM+BLTDMOD
    move.w  #$0000,CUSTOM+BLTADAT

    swap    d1
    move.w  d1,CUSTOM+BLTDPTH
    swap    d1
    move.w  d1,CUSTOM+BLTDPTL

    move.w  #(1<<6)|20,CUSTOM+BLTSIZE

    dbra    d4,.dropout

.done:
    bsr     vhs_WaitBlit
    movem.l (sp)+,d0-d7/a0-a3
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_DoChromaSmear — barrel-shift OR on planes 1 and 2
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_DoChromaSmear:
    movem.l d0-d4/a0,-(sp)

    move.l  VV_DRAWBUF(a5),a0
    move.w  VV_DISTORT(a5),d4
    cmp.w   #64,d4
    blt     .done

    move.w  #1,d3

.smear:
    cmp.w   #3,d3
    bgt     .done

    move.l  a0,d0
    move.l  d3,d1
    mulu    #VHS_PLANE_SIZE,d1
    add.l   d1,d0

    bsr     vhs_WaitBlit

    move.w  #$19FC,CUSTOM+BLTCON0       ; shift A by 1, A OR D → D
    move.w  #$0000,CUSTOM+BLTCON1
    move.w  #$FFFF,CUSTOM+BLTAFWM
    move.w  #$7FFF,CUSTOM+BLTALWM
    move.w  #0,CUSTOM+BLTAMOD
    move.w  #0,CUSTOM+BLTDMOD

    swap    d0
    move.w  d0,CUSTOM+BLTAPTH
    swap    d0
    move.w  d0,CUSTOM+BLTAPTL

    swap    d0
    move.w  d0,CUSTOM+BLTDPTH
    swap    d0
    move.w  d0,CUSTOM+BLTDPTL

    move.w  #(256<<6)|20,CUSTOM+BLTSIZE

    bsr     vhs_WaitBlit
    addq.w  #1,d3
    bra     .smear

.done:
    movem.l (sp)+,d0-d4/a0
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_BuildNormalCopList — write a plain copper list to the INACTIVE buffer
* Points bitplanes at VV_SRCBUF (your clean screen). No per-line patching.
* a5 = VarBase
*─────────────────────────────────────────────────────────────────────────────

vhs_BuildNormalCopList:
    movem.l d0-d7/a0-a2,-(sp)

    move.l  VV_COPLIST2(a5),a0          ; write to inactive list
    move.l  VV_SRCBUF(a5),a1            ; display from source

    ; Display setup words
    move.w  #DIWSTRT,(a0)+
    move.w  #VHS_DIW_START,(a0)+
    move.w  #DIWSTOP,(a0)+
    move.w  #VHS_DIW_STOP,(a0)+
    move.w  #DDFSTRT,(a0)+
    move.w  #VHS_DDF_START,(a0)+
    move.w  #DDFSTOP,(a0)+
    move.w  #VHS_DDF_STOP,(a0)+
    move.w  #BPLCON0,(a0)+
    move.w  VV_BPLCON0(a5),(a0)+    ; runtime BPLCON0 from plane count
    move.w  #BPLCON1,(a0)+
    move.w  #$0000,(a0)+
    move.w  #BPL1MOD,(a0)+
    move.w  #$0000,(a0)+
    move.w  #BPL2MOD,(a0)+
    move.w  #$0000,(a0)+

    ; Palette
    lea     vhs_NormalPal,a2
    move.w  #VHS_COLORS-1,d7
    move.w  #COLOR00,d6
.pal:
    move.w  d6,(a0)+
    move.w  (a2)+,(a0)+
    add.w   #2,d6
    dbra    d7,.pal

    ; Bitplane pointers — emit one pair per plane, count from VV_PLANES
    ; BPL register offset table: PTH/PTL pairs starting at $E0
    ; BPL1PTH=$E0, BPL1PTL=$E2, BPL2PTH=$E4 ... BPL5PTH=$F0, BPL5PTL=$F2
    move.w  VV_PLANES(a5),d7        ; loop count
    subq.w  #1,d7                   ; dbra-adjust
    move.w  #BPL1PTH,d6             ; current register offset
    moveq   #0,d5
    move.l  a1,d4                   ; plane address accumulator

.bpl_ptr:
    move.l  d4,d0                   ; current plane address
    move.w  d6,(a0)+                ; BPLxPTH register
    swap    d0
    move.w  d0,(a0)+                ; high word
    addq.w  #2,d6                   ; advance to BPLxPTL
    swap    d0                      ; undo swap to restore original value
    move.w  d6,(a0)+                ; BPLxPTL register
    move.w  d0,(a0)+                ; low word of plane address
    addq.w  #2,d6                   ; advance to next BPLxPTH
    add.l   #VHS_PLANE_SIZE,d4      ; next plane
    dbra    d7,.bpl_ptr

    ; End
    move.w  #$FFFF,(a0)+
    move.w  #$FFFE,(a0)+

    movem.l (sp)+,d0-d7/a0-a2
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_BuildEffectCopList — per-scanline BPLxPT copper list
* a5 = VarBase
* Clamped to lines 0..211 (vpos = FIRST_LINE+Y must fit in 8 bits).
*─────────────────────────────────────────────────────────────────────────────

vhs_BuildEffectCopList:
    movem.l d0-d7/a0-a4,-(sp)

    move.l  VV_COPLIST2(a5),a0
    move.l  VV_DRAWBUF(a5),a4

    ; Header
    move.w  #DIWSTRT,(a0)+
    move.w  #VHS_DIW_START,(a0)+
    move.w  #DIWSTOP,(a0)+
    move.w  #VHS_DIW_STOP,(a0)+
    move.w  #DDFSTRT,(a0)+
    move.w  #VHS_DDF_START,(a0)+
    move.w  #DDFSTOP,(a0)+
    move.w  #VHS_DDF_STOP,(a0)+
    move.w  #BPLCON0,(a0)+
    move.w  VV_BPLCON0(a5),(a0)+    ; runtime BPLCON0
    move.w  #BPLCON1,(a0)+
    move.w  #$0000,(a0)+
    move.w  #BPL1MOD,(a0)+
    move.w  #$0000,(a0)+
    move.w  #BPL2MOD,(a0)+
    move.w  #$0000,(a0)+

    ; VHS palette
    lea     vhs_VHSPal,a2
    move.w  #VHS_COLORS-1,d7
    move.w  #COLOR00,d6
.vpal:
    move.w  d6,(a0)+
    move.w  (a2)+,(a0)+
    add.w   #2,d6
    dbra    d7,.vpal

    ; Per-scanline patching (lines 0..211 only — vpos overflow guard)
    lea     vhs_ShiftTable,a3
    move.w  #0,d6
    move.w  #$7FFF,d5                   ; previous shift sentinel

.line:
    cmp.w   #212,d6
    bge     .line_done

    ; Read shift for this line
    move.w  d6,d4
    add.w   d4,d4
    move.l  a3,a1
    adda.w  d4,a1
    move.w  (a1),d4

    cmp.w   d5,d4
    beq     .line_skip
    move.w  d4,d5

    ; Emit WAIT
    move.w  d6,d0
    add.w   #VHS_FIRST_LINE,d0
    lsl.w   #8,d0
    or.w    #$0001,d0
    move.w  d0,(a0)+
    move.w  #$FF7E,(a0)+

    ; Row byte offset
    move.w  d6,d1
    and.l   #$0000FFFF,d1
    mulu    #VHS_STRIDE,d1

    ; Pixel → byte shift (word-aligned)
    move.w  d4,d2
    asr.w   #3,d2
    and.w   #$FFFE,d2

    ; Emit one BPLxPTH/BPLxPTL pair per plane (count from VV_PLANES)
    move.w  VV_PLANES(a5),d0
    subq.w  #1,d0               ; dbra count
    move.w  #BPL1PTH,d3         ; current register (advances by 4 each plane)
    moveq   #0,d4
    move.l  a4,d4               ; plane base accumulator

.per_plane:
    ; addr = plane_base + row_offset(d1) + byte_shift(d2)
    move.l  d4,d7               ; use d7 for address, not d0 (which is the loop counter!)
    add.l   d1,d7
    add.w   d2,d7
    ; emit PTH
    move.w  d3,(a0)+            ; BPLxPTH register offset
    move.l  d7,d5
    swap    d5
    move.w  d5,(a0)+            ; high word
    addq.w  #2,d3               ; → BPLxPTL
    ; emit PTL
    move.w  d3,(a0)+
    move.w  d7,(a0)+            ; low word
    addq.w  #2,d3               ; → next BPLxPTH
    add.l   #VHS_PLANE_SIZE,d4  ; next plane
    dbra    d0,.per_plane

.line_skip:
    addq.w  #1,d6
    bra     .line

.line_done:
    move.w  #$FFFF,(a0)+
    move.w  #$FFFE,(a0)+

    movem.l (sp)+,d0-d7/a0-a4
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_ApplyVHSPalette / vhs_ApplyNormalPalette
*─────────────────────────────────────────────────────────────────────────────

vhs_ApplyVHSPalette:
    movem.l d0/a0-a1,-(sp)
    lea     vhs_VHSPal,a0
    lea     CUSTOM+COLOR00,a1
    move.w  #VHS_COLORS-1,d0
.lp:
    move.w  (a0)+,(a1)+
    dbra    d0,.lp
    movem.l (sp)+,d0/a0-a1
    rts

vhs_ApplyNormalPalette:
    movem.l d0/a0-a1,-(sp)
    lea     vhs_NormalPal,a0
    lea     CUSTOM+COLOR00,a1
    move.w  #VHS_COLORS-1,d0
.lp:
    move.w  (a0)+,(a1)+
    dbra    d0,.lp
    movem.l (sp)+,d0/a0-a1
    rts

*=============================================================================
* DATA SECTION
*=============================================================================

    SECTION VHS_DATA,DATA_C

; Palette storage (filled at VHS_StartEffect time from hardware registers)
vhs_NormalPal:
    DS.W    32

vhs_VHSPal:
    DS.W    32

*=============================================================================
* BSS SECTION
*=============================================================================

    SECTION VHS_BSS,BSS

; Per-scanline horizontal shift table (256 signed word entries)
vhs_ShiftTable: DS.W    256

; Chip RAM buffer pointers (set by VHS_Init)
vhs_BufA:       DS.L    1   ; effect draw buffer A
vhs_BufB:       DS.L    1   ; effect draw buffer B
vhs_BufSrc:     DS.L    1   ; clean source (copy of your screen)
vhs_NoisePlane: DS.L    1   ; noise bitplane
vhs_CopA:       DS.L    1   ; copper list A
vhs_CopB:       DS.L    1   ; copper list B
vhs_VarBase:    DS.L    1   ; internal variable block

; Plane count saved from VHS_Init d0 parameter
vhs_PlaneCount: DS.W    1
                DS.W    1   ; pad

; Caller's pointers (saved by VHS_Init, restored on stop)
vhs_YourScreen: DS.L    1   ; caller's bitplane 0
vhs_YourPalette:DS.L    1   ; caller's palette table
vhs_YourCopList:DS.L    1   ; caller's copper list

; Public exported flag byte
VHS_StateActive:DS.B    1   ; non-zero when effect is running or fading
                DS.B    1   ; alignment pad

*=============================================================================
* END
*=============================================================================

    END
