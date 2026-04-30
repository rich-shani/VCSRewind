# VCS VHS Effect Module - Project Memory

## Current State (2026-04-30)

### Files in Progress
1. **VHS_NEW.s** - Simplified VHS effect module using direct copper list manipulation
   - Minimal implementation with per-frame scanline shifting effects
   - Public API: VHS_NewInit, VHS_NewStartEffect, VHS_NewStopEffect, VHS_NewDoFrame
   - Status: Complete, needs testing

2. **VHS_TEST.s** - Example program demonstrating VHS_NEW.s integration
   - Displays colored bars on startup
   - Triggers VHS effect via code (F10 key handling not yet implemented)
   - Status: In progress - displays dark grey screen instead of expected yellow

### Recent Changes
- Added IFND/ENDIF conditional compilation to VHS_NEW.s hardware equates to prevent duplicate definition errors
- Updated VHS_TEST.s MainLoop to call VHS_NewStartEffect and VHS_NewDoFrame
- Fixed screen fill pattern:
  - Was: filling all planes with $FFFFFFFF → shows color index 31 (undefined) → dark grey
  - Now: filling planes 0-2 with $FFFFFFFF, planes 3-4 with $00000000 → color index 7 (yellow)

### Current Issue
VHS_TEST.s displays dark grey screen instead of yellow. Root cause TBD - could be:
- Copper list format or installation error
- Display window (DIWSTRT/DIWSTOP) or fetch (DDFSTRT/DDFSTOP) parameters
- DMA enable sequence
- Bitplane pointer setup in copper list

## Architecture Overview

### VHS_NEW.s Design
- **No buffer allocation** - modifies caller's copper list directly
- **Per-frame scanline shifts** - uses LFSR for pseudo-random shifts (-3 to +4 pixels)
- **Auto-stop** - runs for VHS_EFFECT_DURATION (100 frames by default), then restores display
- **Minimal memory** - only stores state variables and saved copper list pointer

**State Variables:**
- VHS_OriginalCop: Saved caller's copper list pointer
- VHS_OrigBpl1Ptr: Original BPL1PTH value
- VHS_IsActive: Effect running flag
- VHS_FrameCount: Frame counter
- VHS_LFSR: Pseudo-random number generator ($80000057 polynomial)

**Key Functions:**
- VHS_NewInit(a0=copper list): Scans for BPL1PTH and saves original address
- VHS_NewStartEffect(): Sets active flag, initializes frame counter
- VHS_NewStopEffect(): Restores original BPL pointers and reinstalls copper list
- VHS_NewDoFrame(): Called every frame, applies random shifts, auto-stops at duration
- vhs_ApplyRandomEffects(): LFSR-driven horizontal scanline shifts (±2 bytes = ±16 pixels)

**Effect Parameters (tunable in VHS_NEW.s):**
- VHS_EFFECT_LINES: 8 scanlines affected per frame
- VHS_COLOR_SHIFT: 3 (palette shift amount)
- VHS_PIXEL_SHIFT: 4 (horizontal shift amount)
- VHS_FADE_IN: 12 frames to reach full effect
- VHS_FADE_OUT: 12 frames to return to normal
- VHS_EFFECT_DURATION: 100 frames total

### VHS_TEST.s Structure
1. **InitScreen**: Allocates 51200 bytes chip RAM for 5-plane 320x256 screen, fills with pattern
2. **BuildCopperList**: Creates complete copper list with:
   - Display window (DIWSTRT=$2C81, DIWSTOP=$2CC1 for PAL)
   - Fetch (DDFSTRT=$0038, DDFSTOP=$00D0 for 320-wide)
   - Bitplane setup (BPLCON0=$5200 for 5 planes, BPLCON1=$0000)
   - 8-color palette (black, white, red, green, blue, cyan, magenta, yellow)
   - Bitplane pointers (BPL1-5 PTH/PTL) pointing to allocated screen
   - End marker ($FFFF/$FFFE)
3. **InitVHS**: Calls VHS_NewInit with copper list pointer
4. **MainLoop**: Triggers effect, repeatedly calls VHS_NewDoFrame
5. **Cleanup**: Frees allocated screen memory

## Integration Pattern

For users adding VHS_NEW.s to their own codebase:
```
1. Include VHS_NEW.s at end of source file
2. Call VHS_NewInit(a0=copper_list) at startup
3. Call VHS_NewStartEffect() when triggering effect (F10, menu, etc.)
4. Call VHS_NewDoFrame() every frame (main loop or VBlank interrupt)
5. Effect auto-stops after VHS_EFFECT_DURATION frames
6. VHS_NewStopEffect() available if need early stop
```

## Testing Notes

### Original vhs_effect.asm (Complex Implementation)
- Was much more complex with buffer manipulation, palette shifting, multiple effects
- Showed colored bars correctly with palette shifting visible
- Had issues with copper list corruption when patching palette entries
- User feedback: "palette isnt being swapped out", corruption at screen edges

### Simplification Decision
- User requested simpler approach: "perhaps there's a simpler approach, where we can just directly modify the copper to add some color noise, tracking errors on multiple horizontal lines and some scanline shifting"
- Led to VHS_NEW.s design - direct copper list manipulation instead of buffer effects
- Trade-off: Lost palette shifting visibility, gained simplicity and reliability

## Known Issues / Debug Status

1. **VHS_TEST.s Dark Grey Screen**
   - Status: Investigating
   - Last fix: Changed screen fill from color 31 (undefined) to color 7 (yellow)
   - Still shows dark grey - indicates display system issue
   - Next: Check copper list format, display parameters, DMA enable

2. **Hardware Equate Conflicts**
   - Status: Fixed
   - Solution: Wrapped VHS_NEW.s equate definitions with IFND/ENDIF
   - Allows module to be included in any project safely

## Files Reference
- VHS_NEW.s: ~330 lines, complete module
- VHS_TEST.s: ~250 lines, example integration
- vhs_effect.i: Reference documentation (not used in current approach)
- vhs_effect.asm: Original complex implementation (archived)

## Prior Work & Evolution

### vcseffect.s (Main Program - Original Integration)
- Purpose: Test program using vhs_effect.asm module
- Features:
  - F10 key to activate/deactivate VHS effect
  - Left mouse button to quit
  - Full VBlank interrupt handler integration
  - Proper initialization and cleanup
- Screen: 320x256 PAL, 5 bitplanes non-interleaved
- Status: Working proof-of-concept for complex effect

### vhs_effect.asm (Original Complex Module)
- **Size**: ~1500+ lines of complex code
- **Architecture**: Buffer-based with multiple effects pipeline
- **Key Components**:
  - VHS_Init: Allocates work buffers, saves caller's screen/palette/copper
  - VHS_Free: Deallocates chip RAM
  - VHS_StartEffect: Snapshots palette, begins fade-in
  - VHS_StopEffect: Begins fade-out
  - VHS_DoFrame: Main effect processor (called from VBlank)
  - VHS_UpdateScreen: Refreshes source buffer if screen changes

- **Features Implemented**:
  - Fade-in/fade-out state machine (12 frames each)
  - Palette color shifting toward grey
  - Scanline horizontal shifts (tracking error simulation)
  - Screen corruption artifacts (intentional VHS effects)
  - Blitter-based screen copy and effect operations
  - Complex palette generation (shift by 87.5% toward grey, multiply by 13/16 brightness)

- **Major Bugs Fixed During Development**:
  1. **Bitplane pointer corruption** (vhs_BuildNormalCopList):
     - Cause: Incorrect register reuse in swap pattern
     - Fix: Changed to proper: move.l → swap (get high) → move.w (write high) → swap (restore) → move.w (write low)
     - User: "that worked. Now, next bug..."

  2. **Divide overflow exceptions**:
     - Cause: VV_SRCBUF uninitialized when division attempted
     - Fix: Moved vhs_CopyScreenToSrc before variable block initialization
     - User: "I still get an illegal instruction..."

  3. **Alternating effect timing** (short flash then long effect):
     - Cause: VV_FADECOUNT not reset when transitioning from IN to FAST state
     - Fix: Added clr.w VV_FADECOUNT(a5) on state transition
     - User: "it always takes either a short flash of the border, or a long period of effect time"

  4. **Palette shift not visible**:
     - Cause: Copper list COLOR register entries overwriting vhs_ApplyVHSPalette writes
     - Attempted fixes: patching palette in copper list, removing entries - both caused corruption
     - User: "the palette isnt being swapped out", "now I get the grey/white screen again"
     - Final: Abandoned this approach in favor of simpler design

  5. **Display corruption (grey/white screen with one bar)**:
     - Cause: Custom copper list with mismatched DIW/DDF values
     - User: "when I press F10, I get mostly white with the two blue bars"
     - Decision: Switched to modifying caller's copper list instead of building custom one

- **Parameter Tuning Done**:
  - VHS_MAX_SHIFT: Increased from 16 to 32 pixels for more distortion
  - Effect duration: Auto-stop at 100 frames in FAST state
  - Fade timing: 12 frames fade-in, 100 frames effect, 12 frames fade-out

- **Final State**: Working visually but palette shifting not visible; complex codebase (1500+ lines)

### Why vhs_effect.asm Was Abandoned

1. **Complexity vs. Visual Return**
   - 1500+ lines of code to achieve distortion effects
   - Palette shift invisible due to copper list conflicts
   - Difficult to debug display corruption issues

2. **User Feedback Progression**
   - Initial: "no crash, lets add the next one"
   - Mid-development: "I dont think the palette shift is working"
   - Final: "perhaps there's a simpler approach, where we can just directly modify the copper to add some color noise, tracking errors on multiple horizontal lines and some scanline shifting"

3. **Design Decision** (User-driven)
   - "can we add effects and simply the module - ie do we need all the extra screen copies, buffers, etc?"
   - User: "yes - proceed" → led to architectural simplification

### Evolution to VHS_NEW.s

**Shift in Approach:**
1. Abandoned buffer-based effects (complex, hard to debug)
2. Adopted direct copper list manipulation (simpler, minimal memory)
3. Started with scanline shifts only (core VHS effect)
4. Plan to add color noise and glitch effects as optional enhancements

**Key Design Decisions:**
- No chip RAM allocation for buffers
- No palette generation/shifting
- No blitter operations
- Direct copper list pointer manipulation (±2 bytes per frame)
- LFSR-based randomization for varied effects
- Auto-stop timer (100 frames configurable)

**Result**: ~330 lines vs ~1500 lines, minimal memory overhead, easier to integrate

### Lessons Learned

1. **Display Debugging**: Copper list corruption is subtle - palette entries overwriting shifted values
2. **Buffer Complexity**: Multiple buffers (SRC, A, B, effect buffers) added complexity without proportional visual gain
3. **Simplification Strategy**: When complexity causes diminishing returns, restart with simpler architecture
4. **Modularity**: Direct copper manipulation easier to integrate than allocating internal buffers
5. **LFSR Usage**: Effective for pseudo-random scanline variations with minimal overhead

## Next Session Tasks
1. Debug why VHS_TEST.s shows dark grey screen
2. Verify copper list installation and display parameters
3. Once display works, test VHS effect triggering
4. Refine effect parameters (shift amounts, duration) based on visual feedback
5. Implement keyboard input (F10) for effect triggering (reference: vcseffect.s structure)
6. Consider additional effects: color noise, glitch bands (build on VHS_NEW.s foundation)
