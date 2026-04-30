*******************************************************************************
*   VHS_EFFECT.I  —  Include file for VHS Rewind Effect Module               *
*   Add this file to your project and INCLUDE it in your main source.        *
*******************************************************************************
*                                                                             *
*   USAGE IN YOUR MAIN SOURCE:                                                *
*       INCLUDE "vhs_effect.i"                                               *
*                                                                             *
*   BUILD (single pass):                                                      *
*       vasm68k_mot -Fhunkexe -o mygame -kick1hunks \                        *
*           your_game.asm vhs_effect.asm                                     *
*                                                                             *
*   BUILD (separate objects):                                                 *
*       vasm68k_mot -Fhunk -o vhs_effect.o  vhs_effect.asm                  *
*       vasm68k_mot -Fhunk -o your_game.o   your_game.asm                   *
*       vlink -bamigahunk -o mygame your_game.o vhs_effect.o                 *
*                                                                             *
*******************************************************************************
*                                                                             *
*   PUBLIC ROUTINES                                                           *
*   ───────────────                                                           *
*                                                                             *
*   VHS_Init                                                                 *
*       IN  a0 = your bitplane 0 pointer  (chip RAM, non-interleaved)        *
*           a1 = your 32-word palette  (DC.W x 32)                          *
*           a2 = your copper list pointer  (saved; restored on stop)         *
*       OUT d0 = 1 success,  0 failure (not enough chip RAM)                 *
*       Call once at game startup.                                            *
*                                                                             *
*   VHS_Free                                                                 *
*       Frees all chip RAM. Call at game shutdown.                           *
*                                                                             *
*   VHS_StartEffect                                                          *
*       Snapshots current palette, begins fade-in.                           *
*       Check VHS_IsActive=0 before calling.                                 *
*                                                                             *
*   VHS_StopEffect                                                           *
*       Begins fade-out. VHS_DoFrame returns d0=0 when fully stopped.       *
*                                                                             *
*   VHS_DoFrame                                                              *
*       Call from your VBlank interrupt handler every frame.                 *
*       OUT d0 = 1 still running,  0 stopped (copper restored to yours)     *
*       Saves d1-d7/a0-a6.                                                   *
*                                                                             *
*   VHS_IsActive                                                             *
*       OUT d0 = 1 running/fading,  0 fully stopped                         *
*       Or test  VHS_StateActive  byte directly (faster, no call overhead).  *
*                                                                             *
*   VHS_UpdateScreen                                                         *
*       Call if your screen changes while the effect is not running to       *
*       refresh the internal clean source buffer.                            *
*                                                                             *
*******************************************************************************
*                                                                             *
*   TUNABLE EQUATES  (override these BEFORE including this file)             *
*   ─────────────────────────────────────────────────────────────            *
*       VHS_SCREEN_H  = 256  (PAL) or 200 (NTSC)                            *
*       VHS_FADE_IN   = 12   frames to reach full distortion                 *
*       VHS_FADE_OUT  = 12   frames to return to normal                      *
*       VHS_MAX_SHIFT = 16   maximum horizontal tear in pixels               *
*                                                                             *
*   See VHS_EFFECT.ASM constants section to change these.                    *
*                                                                             *
*******************************************************************************

    XREF    VHS_Init
    XREF    VHS_Free
    XREF    VHS_StartEffect
    XREF    VHS_StopEffect
    XREF    VHS_DoFrame
    XREF    VHS_IsActive
    XREF    VHS_UpdateScreen
    XREF    VHS_StateActive     ; byte: non-zero while effect is running/fading

*******************************************************************************
*                                                                             *
*   MINIMAL INTEGRATION TEMPLATE  (copy and adapt)                           *
*                                                                             *
*   ; ── At game startup ─────────────────────────────────────────────────   *
*       lea     MyBitplane0,a0      ; your screen, bitplane 0                *
*       lea     MyPalette,a1        ; 32 x DC.W colour table                 *
*       lea     MyCopperList,a2     ; your game copper list                  *
*       moveq   #5,d0               ; 4 or 5 bitplanes                       *
*       jsr     VHS_Init                                                     *
*       tst.l   d0                                                           *
*       beq     .no_vhs             ; bail if not enough chip RAM            *
*                                                                             *
*   ; ── Inside your VBlank interrupt handler ───────────────────────────   *
*       tst.b   VHS_StateActive     ; fast byte test — no jsr needed        *
*       beq     .vhs_skip                                                    *
*       jsr     VHS_DoFrame         ; run effect + install copper            *
*       tst.l   d0                  ; d0=0 → stopped, copper restored        *
*       bra     .vhs_done           ; skip normal copper install             *
*   .vhs_skip:                                                               *
*       ; ... your normal copper list update here ...                       *
*   .vhs_done:                                                               *
*                                                                             *
*   ; ── To trigger the effect (e.g. level end, pause) ───────────────────  *
*       jsr     VHS_StartEffect                                              *
*                                                                             *
*   ; ── To stop the effect ─────────────────────────────────────────────   *
*       jsr     VHS_StopEffect                                               *
*                                                                             *
*   ; ── To wait for effect to finish before doing something ────────────   *
*   .wait:                                                                   *
*       tst.b   VHS_StateActive                                              *
*       bne     .wait                                                        *
*                                                                             *
*   ; ── If your screen changes while effect is idle ─────────────────────  *
*       jsr     VHS_UpdateScreen                                             *
*                                                                             *
*   ; ── At game shutdown ────────────────────────────────────────────────   *
*       jsr     VHS_Free                                                     *
*                                                                             *
*******************************************************************************
