*******************************************************************************
*                                                                             *
*   VCSEFFECT.S — Amiga 68000 Assembly                                       *
*   VHS Cassette Rewind Effect — Main Program                                *
*                                                                             *
*   Integrates with the VHS Effect module (module/vhs_effect.asm).           *
*                                                                             *
*   Build (two-pass, separate objects):                                       *
*     vasm68k_mot -Fhunk -o vcseffect.o   vcseffect.s                       *
*     vasm68k_mot -Fhunk -o vhs_effect.o  module/vhs_effect.asm             *
*     vlink -bamigahunk -o vcseffect vcseffect.o vhs_effect.o               *
*                                                                             *
*   Or single-pass:                                                           *
*     vasm68k_mot -Fhunkexe -o vcseffect -kick1hunks \                      *
*         vcseffect.s module/vhs_effect.asm                                  *
*                                                                             *
*   Controls:                                                                 *
*     F10              — Hold to activate VHS rewind effect                  *
*     Left Mouse Button — Quit                                               *
*                                                                             *
*   Screen requirements (must match module/vhs_effect.asm):                  *
*     • 320x256 PAL, 5 bitplanes, non-interleaved, chip RAM                 *
*     • Planes contiguous: plane N at ScreenBuf + N*PLANE_SIZE              *
*                                                                             *
*   VHS module API used:                                                      *
*     VHS_Init         — allocates chip buffers, copies screen, saves copper *
*     VHS_StartEffect  — snapshots palette, begins fade-in                   *
*     VHS_StopEffect   — begins fade-out sequence                            *
*     VHS_DoFrame      — call every VBlank while VHS_StateActive != 0       *
*     VHS_Free         — releases all chip buffers                           *
*     VHS_StateActive  — public byte: non-zero while effect running/fading   *
*                                                                             *
*******************************************************************************

*   Include the VHS module interface (XREF declarations for all public symbols)
    INCLUDE "module/vhs_effect.i"

*=============================================================================
* ASSEMBLER OPTIONS
*=============================================================================

    OPT     O+          ; optimisations on
    OPT     W-          ; suppress warnings

*=============================================================================
* HARDWARE REGISTER EQUATES
* Guarded with IFND so they co-exist with module/vhs_effect.asm which
* defines the same symbols using the same guards.
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
INTF_SETCLR     EQU     $8000
INTF_VERTB      EQU     $0020
INTF_INTEN      EQU     $4000
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

; Sprite registers (we disable all sprites at startup)
SPR0PTH         EQU     $120
SPR0PTL         EQU     $122

; CIA-A (keyboard / mouse button)
CIAA_BASE       EQU     $BFE001     ; CIA-A, byte-wide, odd addresses
                                    ; ICR at +$D00, SDR at +$C00, CRA at +$E00

; OS vectors and Exec LVOs
    IFND    EXEC_BASE
EXEC_BASE       EQU     4
LVO_ALLOCMEM    EQU     -198
LVO_FREEMEM     EQU     -210
    ENDC

LVO_FORBID      EQU     -132
LVO_PERMIT      EQU     -138
LVO_DISABLE     EQU     -120
LVO_ENABLE      EQU     -126

    IFND    MEMF_CHIP
MEMF_CHIP       EQU     $00000002
MEMF_CLEAR      EQU     $00010000
    ENDC

; Level 3 autovector (VBlank)
VBL_VECTOR      EQU     $6C

; Keyboard raw keycodes
KEY_F10_RAW     EQU     $59         ; Amiga raw keycode for F10

*=============================================================================
* SCREEN / DISPLAY CONSTANTS
* These must match VHS_SCREEN_W/H/PLANES in module/vhs_effect.asm.
*=============================================================================

SCREEN_W        EQU     320
SCREEN_H        EQU     256
SCREEN_PLANES   EQU     5
SCREEN_COLORS   EQU     32
PLANE_SIZE      EQU     (SCREEN_W/8)*SCREEN_H    ; 40 * 256 = 10240 bytes
SCREEN_SIZE     EQU     PLANE_SIZE*SCREEN_PLANES  ; 51200 bytes
PLANE_STRIDE    EQU     SCREEN_W/8               ; 40 bytes per scanline

; PAL display window — must match VHS_DIW_* in vhs_effect.asm
DIW_START       EQU     $2C81
DIW_STOP        EQU     $2CC1
DDF_START       EQU     $003C
DDF_STOP        EQU     $00D4
BPLCON0_VAL     EQU     $5200       ; 5 planes, colour enable, lores

; Normal copper list: display setup (8 pairs) + palette (32 pairs)
;   + 5 plane pointer pairs (10 pairs) + END = 51 entries * 4 bytes = 204
; Round up to 256 for safety.
COPLIST_SIZE    EQU     256

*=============================================================================
* MAIN VARIABLE BLOCK OFFSETS
* A small chip-RAM block for our own runtime state.
*=============================================================================

VAR_QUITFLAG    EQU     0   ; byte  — non-zero when LMB pressed (quit)
VAR_KEYFLAG     EQU     1   ; byte  — 1 while F10 held, 0 when released
VAR_PREVKEY     EQU     2   ; byte  — F10 state on the previous VBlank frame
                            ; byte pad at offset 3
VAR_ORIGVBL     EQU     4   ; long  — original VBL autovector (level 3)
VAR_ORIGDMA     EQU     8   ; word  — saved DMACON (with SET bit)
VAR_ORIGINTE    EQU     10  ; word  — saved INTENA  (with SET bit)
VAR_SIZE        EQU     12  ; total bytes in variable block

*=============================================================================
* PROGRAM START
*=============================================================================

    SECTION CODE,CODE_C

Start:
    movem.l d0-d7/a0-a6,-(sp)

    move.l  EXEC_BASE,a6
    jsr     LVO_FORBID(a6)          ; prevent task switches during setup

    ; ── Allocate chip RAM: screen buffer, copper list, variable block ──
    bsr     AllocMem
    tst.l   d0
    beq     .fail_alloc

    ; ── Draw a colourful test pattern so the effect has something to distort ──
    bsr     BuildTestScreen

    ; ── Build the normal (non-effect) copper list pointing at our screen ──
    bsr     BuildNormalCopList

    ; ── Initialise VHS module ──────────────────────────────────────────────
    ; a0 = chip-RAM address of our bitplane 0 (plane base)
    ; a1 = our 32-word palette table (module snapshots hardware regs on start,
    ;       but we pass this so VHS_BuildNormalCopList can embed it at stop)
    ; a2 = chip-RAM address of our normal copper list (saved; restored on stop)
    ; d0 = number of bitplanes (4 or 5)
    move.l  ScreenBuf,a0
    lea     NormalPalette,a1
    move.l  CopList,a2
    moveq   #SCREEN_PLANES,d0
    jsr     VHS_Init
    tst.l   d0
    beq     .fail_vhs               ; not enough chip RAM for module buffers

    ; ── Take over the hardware and start the display ──
    bsr     TakeOverHardware

    ; ── Spin here — all work happens inside VBlankHandler ──
    bsr     MainLoop

    ; ── Clean up ──
    jsr     VHS_Free                ; release module chip buffers
    bsr     RestoreHardware         ; restore OS state
    bsr     FreeMem                 ; release our chip allocations
    bra     .exit

.fail_vhs:
    ; VHS_Init already freed any partial module allocations internally.
    ; We only need to free our own allocations.
    bsr     FreeMem
    bra     .exit

.fail_alloc:
    bsr     FreeMem

.exit:
    move.l  EXEC_BASE,a6
    jsr     LVO_PERMIT(a6)          ; re-enable task switching

    movem.l (sp)+,d0-d7/a0-a6
    moveq   #0,d0
    rts

*=============================================================================
* ALLOCATE CHIP MEMORY
* Allocates: one screen buffer, one copper list buffer, one variable block.
* Pointers stored in BSS variables ScreenBuf / CopList / VarBase.
* Returns d0 = 1 success, 0 failure.
*=============================================================================

AllocMem:
    movem.l d1/a1/a6,-(sp)
    move.l  EXEC_BASE,a6

    ; ── Screen buffer (5 non-interleaved planes, chip RAM, zeroed) ──
    move.l  #SCREEN_SIZE,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,ScreenBuf

    ; ── Normal copper list buffer (chip RAM — copper DMA requires chip) ──
    move.l  #COPLIST_SIZE,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,CopList

    ; ── Variable block for our own runtime state ──
    move.l  #VAR_SIZE,d0
    move.l  #MEMF_CHIP|MEMF_CLEAR,d1
    jsr     LVO_ALLOCMEM(a6)
    tst.l   d0
    beq     .fail
    move.l  d0,VarBase

    moveq   #1,d0
    movem.l (sp)+,d1/a1/a6
    rts

.fail:
    moveq   #0,d0
    movem.l (sp)+,d1/a1/a6
    rts

*=============================================================================
* FREE CHIP MEMORY
* Releases all allocations made by AllocMem. Safe to call if AllocMem
* failed partway through (checks each pointer before freeing).
*=============================================================================

FreeMem:
    movem.l d0-d1/a1/a6,-(sp)
    move.l  EXEC_BASE,a6

    move.l  ScreenBuf,d0
    beq     .f1
    move.l  d0,a1
    move.l  #SCREEN_SIZE,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   ScreenBuf
.f1:
    move.l  CopList,d0
    beq     .f2
    move.l  d0,a1
    move.l  #COPLIST_SIZE,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   CopList
.f2:
    move.l  VarBase,d0
    beq     .f3
    move.l  d0,a1
    move.l  #VAR_SIZE,d0
    jsr     LVO_FREEMEM(a6)
    clr.l   VarBase
.f3:
    movem.l (sp)+,d0-d1/a1/a6
    rts

*=============================================================================
* BUILD TEST SCREEN
* Fills ScreenBuf with horizontal colour bands, one 8-line band per palette
* entry (32 bands * 8 lines = 256 lines). In 5-bitplane non-interleaved mode,
* each row in plane P is all-ones when bit P of the band index is 1.
* The resulting colour pattern makes horizontal tearing clearly visible.
*=============================================================================

BuildTestScreen:
    movem.l d0-d7/a0-a2,-(sp)

    move.l  ScreenBuf,a2        ; base of all five planes

    moveq   #0,d5               ; plane counter P = 0..4
.plane_loop:
    ; Compute base of plane P: a1 = a2 + P * PLANE_SIZE
    move.l  a2,a1
    move.l  d5,d0
    mulu    #PLANE_SIZE,d0
    add.l   d0,a1

    moveq   #0,d6               ; scanline Y = 0..255
.row_loop:
    move.w  d6,d0
    lsr.w   #3,d0               ; d0 = band index = Y/8, range 0..31

    btst    d5,d0               ; is bit P of band index set?
    beq     .fill_zero

    ; Fill this row with $FFFF (all pixels of plane P lit for this band)
    move.w  #(PLANE_STRIDE/2)-1,d7
.fill_one:
    move.w  #$FFFF,(a1)+
    dbra    d7,.fill_one
    bra     .next_row

.fill_zero:
    ; Fill this row with $0000
    move.w  #(PLANE_STRIDE/2)-1,d7
.fill_zer:
    clr.w   (a1)+
    dbra    d7,.fill_zer

.next_row:
    addq.w  #1,d6
    cmp.w   #SCREEN_H,d6
    blt     .row_loop

    addq.w  #1,d5
    cmp.w   #SCREEN_PLANES,d5
    blt     .plane_loop

    movem.l (sp)+,d0-d7/a0-a2
    rts

*=============================================================================
* BUILD NORMAL COPPER LIST
* Writes a static copper list into CopList (chip RAM):
*   Display-window and data-fetch setup
*   NormalPalette (32 colour MOVE instructions)
*   Bitplane pointers for all 5 planes of ScreenBuf
*   Copper END
*
* This list is installed at startup and restored by VHS_DoFrame when the
* effect finishes its fade-out. It never needs to be rebuilt because our
* screen is static (BuildTestScreen runs once).
*=============================================================================

BuildNormalCopList:
    movem.l d0-d7/a0-a2,-(sp)

    move.l  CopList,a0          ; destination: chip-RAM copper list buffer
    move.l  ScreenBuf,a1        ; source of bitplane addresses

    ; ── Display window and data fetch ──
    move.w  #DIWSTRT,(a0)+
    move.w  #DIW_START,(a0)+
    move.w  #DIWSTOP,(a0)+
    move.w  #DIW_STOP,(a0)+
    move.w  #DDFSTRT,(a0)+
    move.w  #DDF_START,(a0)+
    move.w  #DDFSTOP,(a0)+
    move.w  #DDF_STOP,(a0)+
    move.w  #BPLCON0,(a0)+
    move.w  #BPLCON0_VAL,(a0)+
    move.w  #BPLCON1,(a0)+
    move.w  #$0000,(a0)+        ; no horizontal scroll
    move.w  #BPL1MOD,(a0)+
    move.w  #$0000,(a0)+        ; modulo = 0 (planes are contiguous)
    move.w  #BPL2MOD,(a0)+
    move.w  #$0000,(a0)+

    ; ── Palette ──
    lea     NormalPalette,a2
    move.w  #SCREEN_COLORS-1,d7
    move.w  #COLOR00,d6
.pal:
    move.w  d6,(a0)+            ; register offset
    move.w  (a2)+,(a0)+         ; colour value
    add.w   #2,d6
    dbra    d7,.pal

    ; ── Bitplane pointers (5 planes) ──
    ; BPL1PTH=$E0, BPL1PTL=$E2, BPL2PTH=$E4 … BPL5PTH=$F0, BPL5PTL=$F2
    move.l  a1,d4               ; plane address accumulator = ScreenBuf base
    move.w  #BPL1PTH,d6         ; current BPLxPTH register offset

    moveq   #SCREEN_PLANES-1,d7 ; dbra counter
.bpl_ptr:
    move.l  d4,d0
    move.w  d6,(a0)+            ; BPLxPTH register offset
    swap    d0
    move.w  d0,(a0)+            ; high word of plane address
    addq.w  #2,d6               ; → BPLxPTL
    move.l  d4,d0
    move.w  d6,(a0)+            ; BPLxPTL register offset
    swap    d0
    move.w  d0,(a0)+            ; low word of plane address
    addq.w  #2,d6               ; → next BPLxPTH
    add.l   #PLANE_SIZE,d4      ; advance to next plane
    dbra    d7,.bpl_ptr

    ; ── Copper END ──
    move.w  #$FFFF,(a0)+
    move.w  #$FFFE,(a0)+

    movem.l (sp)+,d0-d7/a0-a2
    rts

*=============================================================================
* TAKE OVER HARDWARE
* Saves OS interrupt/DMA state, kills task switching, installs our VBlank
* handler, disables sprites, sets display registers, and starts the copper.
*=============================================================================

TakeOverHardware:
    movem.l d0-d7/a0-a6,-(sp)

    move.l  EXEC_BASE,a6
    move.l  VarBase,a5

    ; ── Save OS state ──
    move.l  VBL_VECTOR.w,VAR_ORIGVBL(a5)
    move.w  CUSTOM+DMACONR,d0
    or.w    #$8000,d0                   ; set the SET bit so restore works
    move.w  d0,VAR_ORIGDMA(a5)
    move.w  CUSTOM+INTENAR,d0
    or.w    #$8000,d0
    move.w  d0,VAR_ORIGINTE(a5)

    ; ── Kill OS (Exec Disable stops task switching and interrupts via Exec) ──
    jsr     LVO_DISABLE(a6)

    ; ── Kill all DMA and interrupts at hardware level ──
    move.w  #$7FFF,CUSTOM+DMACON
    move.w  #$7FFF,CUSTOM+INTENA

    ; ── Install our VBlank interrupt handler at level 3 autovector ──
    lea     VBlankHandler,a0
    move.l  a0,VBL_VECTOR.w

    ; ── Disable sprites (point SPR0 at our null sprite data) ──
    lea     NullSprite,a0
    move.l  a0,d0
    swap    d0
    move.w  d0,CUSTOM+SPR0PTH
    swap    d0
    move.w  d0,CUSTOM+SPR0PTL

    ; ── Basic display registers ──
    lea     CUSTOM,a6
    move.w  #BPLCON0_VAL,BPLCON0(a6)
    move.w  #$0000,BPLCON1(a6)
    move.w  #$0024,BPLCON2(a6)         ; sprite priority
    move.w  #0,BPL1MOD(a6)
    move.w  #0,BPL2MOD(a6)
    move.w  #DIW_START,DIWSTRT(a6)
    move.w  #DIW_STOP,DIWSTOP(a6)
    move.w  #DDF_START,DDFSTRT(a6)
    move.w  #DDF_STOP,DDFSTOP(a6)

    ; ── Enable DMA (copper, blitter, raster, master) ──
    move.w  #DMAF_SETCLR|DMAF_COPPER|DMAF_BLITTER|DMAF_RASTER|DMAF_MASTER,CUSTOM+DMACON

    ; ── Point copper at our normal list (high word first — OCS requirement) ──
    move.l  CopList,d0
    swap    d0
    move.w  d0,CUSTOM+COP1LCH
    swap    d0
    move.w  d0,CUSTOM+COP1LCL
    move.w  #$0000,CUSTOM+COPJMP1      ; strobe: copper jumps to COP1LC now

    ; ── Enable VBlank interrupt ──
    move.w  #INTF_SETCLR|INTF_VERTB|INTF_INTEN,CUSTOM+INTENA

    movem.l (sp)+,d0-d7/a0-a6
    rts

*=============================================================================
* RESTORE HARDWARE
* Returns the Amiga to its pre-takeover state and re-enables the OS.
*=============================================================================

RestoreHardware:
    movem.l d0-d7/a0-a6,-(sp)

    ; Silence hardware before touching interrupt vectors
    move.w  #$7FFF,CUSTOM+INTENA
    move.w  #$7FFF,CUSTOM+DMACON

    move.l  VarBase,a5
    move.l  VAR_ORIGVBL(a5),VBL_VECTOR.w
    move.w  VAR_ORIGDMA(a5),CUSTOM+DMACON
    move.w  VAR_ORIGINTE(a5),CUSTOM+INTENA

    ; Re-enable OS (matches LVO_DISABLE in TakeOverHardware)
    move.l  EXEC_BASE,a6
    jsr     LVO_ENABLE(a6)

    movem.l (sp)+,d0-d7/a0-a6
    rts

*=============================================================================
* MAIN LOOP
* Busy-spins until VBlankHandler sets the quit flag (LMB pressed).
* All display work is done inside the interrupt handler.
*=============================================================================

MainLoop:
    move.l  VarBase,a5
.spin:
    tst.b   VAR_QUITFLAG(a5)
    bne     .done
    bra     .spin
.done:
    rts

*=============================================================================
* VBLANK INTERRUPT HANDLER
* Fires at ~50 Hz (PAL). Saves/restores all registers (mandatory for RTe).
*
* Responsibilities:
*   1. Acknowledge the hardware interrupt (write INTREQ twice — OCS bug)
*   2. Check left mouse button → set quit flag
*   3. Poll CIA-A keyboard for F10
*   4. Detect F10 rising/falling edge:
*        Rising  (not-held → held)  → VHS_StartEffect (if effect is idle)
*        Falling (held → not-held)  → VHS_StopEffect  (begins fade-out)
*   5. Call VHS_DoFrame every frame the effect is active:
*        VHS_DoFrame installs the effect copper while running.
*        VHS_DoFrame restores our CopList copper when fade-out completes.
*
* When the effect is not active the hardware copper remains pointed at our
* static CopList — no per-frame copper rebuild is needed.
*=============================================================================

VBlankHandler:
    movem.l d0-d7/a0-a6,-(sp)

    ; Acknowledge VBlank (write twice — OCS chip propagation workaround)
    move.w  #INTF_VERTB,CUSTOM+INTREQ
    nop
    move.w  #INTF_VERTB,CUSTOM+INTREQ

    move.l  VarBase,a5

    ; ── Left mouse button: quit ──
    btst    #6,CIAA_BASE+0          ; bit 6 of CIA-A PRA = left button (0=pressed)
    bne     .no_quit
    move.b  #1,VAR_QUITFLAG(a5)
    bra     .vbl_done
.no_quit:

    ; ── Poll keyboard for F10 (updates VAR_KEYFLAG) ──
    bsr     PollKeyboard

    ; ── F10 edge detection ──────────────────────────────────────────────
    ; Read current and previous key state; save current as new previous.
    move.b  VAR_KEYFLAG(a5),d0     ; d0 = current  (1=held, 0=released)
    move.b  VAR_PREVKEY(a5),d1     ; d1 = previous (1=held, 0=released)
    move.b  d0,VAR_PREVKEY(a5)     ; update history for next frame

    tst.b   d1
    bne     .was_held

    ; ── Previous frame: F10 was NOT held ──
    tst.b   d0
    beq     .do_frame               ; still not held — nothing to do

    ; Rising edge (F10 just pressed): start effect if it is fully stopped
    tst.b   VHS_StateActive
    bne     .do_frame               ; module still fading out from last press
    jsr     VHS_StartEffect         ; snapshot palette, begin fade-in
    bra     .do_frame

.was_held:
    ; ── Previous frame: F10 WAS held ──
    tst.b   d0
    bne     .do_frame               ; still held — effect keeps running

    ; Falling edge (F10 just released): begin fade-out if effect is active
    tst.b   VHS_StateActive
    beq     .do_frame               ; already stopped (nothing to fade)
    jsr     VHS_StopEffect          ; sets state to ST_OUT; DoFrame runs fade-out

.do_frame:
    ; ── Run one frame of the VHS effect pipeline ──────────────────────
    ; VHS_DoFrame does nothing and returns d0=0 if VHS_StateActive=0.
    ; While active (d0=1): builds effect copper, installs it to hardware.
    ; On the last frame of fade-out (d0=0): restores CopList to hardware.
    tst.b   VHS_StateActive
    beq     .vbl_done               ; fast path: effect idle, copper unchanged
    jsr     VHS_DoFrame
    ; d0 = 1 → effect copper now installed (normal flow continues)
    ; d0 = 0 → effect done, CopList copper restored by module

.vbl_done:
    movem.l (sp)+,d0-d7/a0-a6
    rte

*=============================================================================
* POLL KEYBOARD
* Reads CIA-A serial data register. If a new keycode byte is waiting:
*   — performs the mandatory ≥85 µs SP handshake
*   — decodes the Amiga serial format: NOT(rawkey ROL 1)
*   — updates VAR_KEYFLAG for F10 (all other keys are acknowledged silently)
*
* Amiga keyboard serial format (received via CIA-A SDR):
*   transmitted byte = NOT(rawkey ROL 1)
*   decoded: NOT the byte, then ROR 1 → bit7=up-flag, bits6-0=rawcode
*
* CIA-A registers (byte-wide at odd addresses from $BFE001):
*   ICR +$D00  interrupt control — bit3=SP ready; reading clears all bits
*   SDR +$C00  serial data register — the received keycode byte
*   CRA +$E00  control A — bit6=SP direction; pulse high ≥85µs to handshake
*
* Requires: a5 = VarBase
*=============================================================================

PollKeyboard:
    movem.l d0-d1/a0,-(sp)
    lea     CIAA_BASE,a0            ; a0 = $BFE001

    ; Bit 3 of ICR = serial port data ready; reading clears the register
    move.b  $D00(a0),d0
    btst    #3,d0
    beq     .no_key                 ; no new byte — done

    ; Read the received keycode from the serial data register
    move.b  $C00(a0),d0             ; raw byte = NOT(key ROL 1)
    not.b   d0                      ; → (key ROL 1)
    ror.b   #1,d0                   ; → (upflag<<7) | keycode

    ; Handshake: drive SP line high for ≥85 µs (≈600 cycles at 7.09 MHz)
    ; then release — keyboard controller will send the next byte after this.
    or.b    #$40,$E00(a0)           ; CRA bit6=1 → SP output (pulls line low)
    move.w  #150,d1
.hs_delay:
    dbra    d1,.hs_delay            ; ~4 cycles/iteration × 151 ≈ 604 cycles
    and.b   #$BF,$E00(a0)          ; CRA bit6=0 → SP input (releases line)

    ; Decode: bit7=up, bits6-0=keycode
    move.b  d0,d1                   ; save copy for up/down test
    and.b   #$7F,d0                 ; d0 = keycode only

    ; Only act on F10 ($59); all other keys were already handshaked above
    cmp.b   #KEY_F10_RAW,d0
    bne     .no_key

    ; F10: set VAR_KEYFLAG on key-down, clear on key-up
    btst    #7,d1                   ; bit7: 1=key-up, 0=key-down
    bne     .f10_up
    move.b  #1,VAR_KEYFLAG(a5)
    bra     .no_key
.f10_up:
    move.b  #0,VAR_KEYFLAG(a5)

.no_key:
    movem.l (sp)+,d0-d1/a0
    rts

*=============================================================================
* DATA SECTION (chip RAM — must be accessible by copper/DMA)
*=============================================================================

    SECTION DATA,DATA_C

; Null sprite — disables hardware sprites (pointed to by SPR0PT at startup)
NullSprite:
    DC.W    $0000,$0000             ; sprite control words (end-of-sprite mark)
    DC.W    $0000,$0000

; 32-colour normal palette (classic Amiga warm demo palette).
; Passed to VHS_Init as a1 so the module can use it when rebuilding the
; clean copper list after the effect stops.
; The VHS module snapshots the HARDWARE colour registers at VHS_StartEffect
; time to build its desaturated VHS palette — do not rely on these values
; being read at effect time; they are for the initial copper list load.
NormalPalette:
    DC.W    $0000   ; colour  0  — black (background)
    DC.W    $0FFF   ; colour  1  — white
    DC.W    $0F00   ; colour  2  — red
    DC.W    $00F0   ; colour  3  — green
    DC.W    $000F   ; colour  4  — blue
    DC.W    $0FF0   ; colour  5  — yellow
    DC.W    $00FF   ; colour  6  — cyan
    DC.W    $0F0F   ; colour  7  — magenta
    DC.W    $0F80   ; colour  8  — orange
    DC.W    $008F   ; colour  9  — sky blue
    DC.W    $080F   ; colour 10  — purple
    DC.W    $0F88   ; colour 11  — salmon
    DC.W    $0880   ; colour 12  — dark green
    DC.W    $0088   ; colour 13  — dark blue
    DC.W    $0808   ; colour 14  — dark purple
    DC.W    $0888   ; colour 15  — grey
    DC.W    $0444   ; colour 16  — dark grey
    DC.W    $0F44   ; colour 17  — coral
    DC.W    $04F4   ; colour 18  — lime
    DC.W    $044F   ; colour 19  — periwinkle
    DC.W    $0FA0   ; colour 20  — amber
    DC.W    $00FA   ; colour 21  — teal
    DC.W    $0F0A   ; colour 22  — pink
    DC.W    $0AA0   ; colour 23  — olive
    DC.W    $00AA   ; colour 24  — ocean
    DC.W    $0A0A   ; colour 25  — violet
    DC.W    $0AAA   ; colour 26  — silver
    DC.W    $0CCC   ; colour 27  — light grey
    DC.W    $0FC0   ; colour 28  — chartreuse
    DC.W    $00CF   ; colour 29  — azure
    DC.W    $0C0F   ; colour 30  — lavender
    DC.W    $0FFC   ; colour 31  — pale yellow

*=============================================================================
* BSS SECTION
* These three variables hold chip-RAM addresses populated by AllocMem.
*=============================================================================

    SECTION BSS,BSS

ScreenBuf:  DS.L    1   ; chip-RAM address of 5-plane non-interleaved screen
CopList:    DS.L    1   ; chip-RAM address of normal display copper list
VarBase:    DS.L    1   ; chip-RAM address of our runtime variable block

*=============================================================================
* END
*=============================================================================

    END     Start
