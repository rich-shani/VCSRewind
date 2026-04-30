*******************************************************************************
*
*   VHS_NEW.S  —  Amiga 68000 Assembly
*   Simplified VHS Cassette Rewind Screen Effect
*   Copper List-Based (Direct Display Manipulation)
*
*   This module creates VHS-like artifacts by directly modifying your copper
*   list during the effect period. No buffer manipulation, minimal memory use.
*
*******************************************************************************
*
*   PUBLIC API
*   ──────────
*
*   VHS_NewInit
*     Call once at startup to initialize the module.
*     IN:  a0 = pointer to your copper list
*     OUT: d0 = 1 success, 0 failure
*
*   VHS_NewStartEffect
*     Begin the VHS effect. Modifies your copper list on the fly.
*     IN:  (none)
*     OUT: (none)
*
*   VHS_NewStopEffect
*     Stop the effect and restore original copper list.
*     IN:  (none)
*     OUT: (none)
*
*   VHS_NewDoFrame
*     Call from your VBlank interrupt. Applies random scanline effects.
*     IN:  (none)
*     OUT: d0 = 1 if effect active, 0 if stopped
*
*******************************************************************************

    OPT O+
    OPT W-

*=============================================================================
* HARDWARE EQUATES (conditional - define only if not already present)
*=============================================================================

IFND    CUSTOM
CUSTOM          EQU     $DFF000
DMACONR         EQU     $002
COP1LCH         EQU     $080
COP1LCL         EQU     $082
COPJMP1         EQU     $088

COLOR00         EQU     $180
DIWSTRT         EQU     $08E
DIWSTOP         EQU     $090
DDFSTRT         EQU     $092
DDFSTOP         EQU     $094
BPL1PTH         EQU     $0E0
BPL1PTL         EQU     $0E2
ENDIF

*=============================================================================
* EFFECT PARAMETERS (tunable)
*=============================================================================

VHS_EFFECT_LINES    EQU     8           ; how many scanlines get effects per frame
VHS_COLOR_SHIFT     EQU     3           ; palette shift amount (0-15)
VHS_PIXEL_SHIFT     EQU     4           ; horizontal pixel shift (0-16)
VHS_FADE_IN         EQU     12          ; frames to reach full effect
VHS_FADE_OUT        EQU     12          ; frames to return to normal
VHS_EFFECT_DURATION EQU     100         ; total frames in full effect

*=============================================================================
* INTERNAL STATE
*=============================================================================

    SECTION VHS_DATA,DATA

VHS_OriginalCop:    DS.L    1           ; saved caller's copper list
VHS_OrigBpl1Ptr:    DS.L    1           ; saved original BPL1PTH address value
VHS_OrigBpl2Ptr:    DS.L    1           ; saved original BPL2PTH address value
VHS_IsActive:       DS.B    1           ; effect running flag
VHS_State:          DS.B    1           ; 0=normal, 1=fadein, 2=fast, 3=fadeout
VHS_FrameCount:     DS.W    1           ; frame counter
VHS_LFSR:           DS.L    1           ; pseudo-random number generator
VHS_CurrentShift:   DS.W    1           ; current pixel shift amount

*=============================================================================
* CODE SECTION
*=============================================================================

    SECTION VHS_CODE,CODE

*─────────────────────────────────────────────────────────────────────────────
* VHS_NewInit
* Save the caller's copper list and scan for BPL pointers.
* IN:  a0 = caller's copper list
* OUT: d0 = 1 (always succeeds)
*─────────────────────────────────────────────────────────────────────────────

VHS_NewInit:
    movem.l d0-d1/a0-a1,-(sp)

    lea     VHS_OriginalCop,a1
    move.l  a0,(a1)

    ; Initialize LFSR
    lea     VHS_LFSR,a1
    move.l  #$DEADBEEF,(a1)

    ; Scan copper list for BPL1PTH value to save
    move.l  a0,a1
.scan_loop:
    cmp.w   #$FFFF,(a1)             ; end of copper?
    beq     .scan_done
    move.w  (a1),d0                 ; read register
    cmp.w   #BPL1PTH,d0
    beq     .found_bpl1
    add.l   #4,a1                   ; next copper word pair
    bra     .scan_loop

.found_bpl1:
    ; Save the original BPL1PTH value (high word)
    move.w  2(a1),d0
    move.w  d0,-(sp)
    move.w  4(a1),d0                ; low word
    move.w  d0,-(sp)
    move.l  (sp)+,d0
    lea     VHS_OrigBpl1Ptr,a1
    move.l  d0,(a1)

.scan_done:
    movem.l (sp)+,d0-d1/a0-a1
    moveq   #1,d0
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_NewStartEffect
* Begin the VHS effect.
*─────────────────────────────────────────────────────────────────────────────

VHS_NewStartEffect:
    movem.l d0-d1/a0-a1,-(sp)

    lea     VHS_IsActive,a0
    move.b  #1,(a0)                 ; set active flag

    lea     VHS_State,a0
    move.b  #1,(a0)                 ; state = fade-in

    lea     VHS_FrameCount,a0
    move.w  #0,(a0)                 ; reset frame counter

    movem.l (sp)+,d0-d1/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_NewStopEffect
* Stop the VHS effect and restore original copper list.
*─────────────────────────────────────────────────────────────────────────────

VHS_NewStopEffect:
    movem.l d0-d1/a0-a1,-(sp)

    ; Restore original BPL1PTH/BPL1PTL values in the copper list
    lea     VHS_OriginalCop,a0
    move.l  (a0),a1              ; a1 = copper list

.restore_loop:
    cmp.w   #$FFFF,(a1)          ; end of copper?
    beq     .restore_done
    move.w  (a1),d0              ; read register
    cmp.w   #BPL1PTH,d0
    bne     .restore_next

    ; Found BPL1PTH - restore original value
    lea     VHS_OrigBpl1Ptr,a0
    move.l  (a0),d0
    swap    d0
    move.w  d0,2(a1)             ; write high word
    swap    d0
    add.l   #4,a1                ; move to BPL1PTL
    move.w  d0,2(a1)             ; write low word
    bra     .restore_done

.restore_next:
    add.l   #4,a1                ; next copper word pair
    bra     .restore_loop

.restore_done:
    ; Now reinstall the restored copper list
    lea     VHS_OriginalCop,a0
    move.l  (a0),d0
    swap    d0
    move.w  d0,CUSTOM+COP1LCH
    swap    d0
    move.w  d0,CUSTOM+COP1LCL
    move.w  #0,CUSTOM+COPJMP1

    ; Clear active flag
    lea     VHS_IsActive,a0
    clr.b   (a0)

    movem.l (sp)+,d0-d1/a0-a1
    rts

*─────────────────────────────────────────────────────────────────────────────
* VHS_NewDoFrame
* Apply per-frame VHS effects to the display.
* Called every VBlank while effect is active.
* OUT: d0 = 1 if active, 0 if stopped
*─────────────────────────────────────────────────────────────────────────────

VHS_NewDoFrame:
    movem.l d1-d7/a0-a6,-(sp)

    lea     VHS_IsActive,a0
    tst.b   (a0)
    beq     .inactive

    ; Update frame counter and state
    lea     VHS_FrameCount,a0
    addq.w  #1,(a0)
    move.w  (a0),d0

    ; Check if effect duration expired
    cmp.w   #VHS_EFFECT_DURATION,d0
    blt     .still_active

    ; Effect finished - restore and stop
    bsr     VHS_NewStopEffect
    moveq   #0,d0
    bra     .done

.still_active:
    ; Apply random scanline effects
    bsr     vhs_ApplyRandomEffects
    moveq   #1,d0

.done:
    movem.l (sp)+,d1-d7/a0-a6
    rts

.inactive:
    moveq   #0,d0
    movem.l (sp)+,d1-d7/a0-a6
    rts

*─────────────────────────────────────────────────────────────────────────────
* vhs_ApplyRandomEffects
* Apply horizontal scanline shifts to create VHS tracking error effect.
* Uses LFSR to pseudo-randomly shift scanlines by a few pixels.
*─────────────────────────────────────────────────────────────────────────────

vhs_ApplyRandomEffects:
    movem.l d0-d7/a0-a6,-(sp)

    ; Advance LFSR for randomness
    lea     VHS_LFSR,a0
    move.l  (a0),d0
    lsr.l   #1,d0
    bcc     .no_xor
    eor.l   #$80000057,d0        ; LFSR polynomial
.no_xor:
    move.l  d0,(a0)

    ; Generate random shift: use low bits of LFSR (0-8 pixels)
    and.w   #$0F,d0              ; mask to 4 bits
    asr.w   #1,d0                ; divide by 2 (0-7)
    sub.w   #3,d0                ; range: -3 to +4 pixels
    move.w  d0,-(sp)             ; save shift amount

    ; Convert shift amount to byte offset for BPL pointers
    ; Each pixel = 1/8 byte, so shift by (pixels / 8) bytes
    ; For simplicity: shift by 0 or 2 bytes based on sign
    move.w  (sp),d1
    tst.w   d1
    bpl     .shift_pos
    moveq   #-2,d2               ; negative shift = -2 bytes
    bra     .apply_shift
.shift_pos:
    moveq   #2,d2                ; positive shift = +2 bytes

.apply_shift:
    ; Get original BPL1PTH address
    lea     VHS_OrigBpl1Ptr,a0
    move.l  (a0),d0              ; original address

    ; Add the byte shift
    add.l   d2,d0                ; d0 = shifted address

    ; Scan caller's copper list and modify BPL1PTH/BPL1PTL
    lea     VHS_OriginalCop,a0
    move.l  (a0),a1              ; a1 = copper list

.mod_loop:
    cmp.w   #$FFFF,(a1)          ; end of copper?
    beq     .mod_done
    move.w  (a1),d1              ; read register
    cmp.w   #BPL1PTH,d1
    bne     .mod_next

    ; Found BPL1PTH - modify the value
    swap    d0
    move.w  d0,2(a1)             ; write high word of shifted address
    swap    d0
    add.l   #4,a1                ; move to BPL1PTL
    cmp.w   #BPL1PTL,(a1)
    bne     .mod_next
    move.w  d0,2(a1)             ; write low word of shifted address
    bra     .mod_done            ; done after first BPL pair

.mod_next:
    add.l   #4,a1                ; next copper word pair
    bra     .mod_loop

.mod_done:
    ; Reinstall copper list to apply changes
    lea     VHS_OriginalCop,a0
    move.l  (a0),d0
    swap    d0
    move.w  d0,CUSTOM+COP1LCH
    swap    d0
    move.w  d0,CUSTOM+COP1LCL
    move.w  #0,CUSTOM+COPJMP1

    add.l   #2,sp                ; clean up shift amount from stack

    movem.l (sp)+,d0-d7/a0-a6
    rts

*=============================================================================
* END
*=============================================================================

    END
