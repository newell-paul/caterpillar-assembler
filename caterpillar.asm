; ============================================================================
; Caterpillar - BBC Micro 6502 Assembly (MODE 7 BASIC wrapper version) v0.0.9
; Converted from BBC BASIC by Paul Newell with some ssistance from Claude Code (c) 2026
; Game engine only - title/menu/scores handled by BASIC in MODE 7
; ============================================================================

; --- MOS Entry Points ---
OSWRCH  = &FFEE
OSRDCH  = &FFE0
OSBYTE  = &FFF4
OSWORD  = &FFF1

; --- Zero Page Variables ---
; Using &60-&9F for game variables
scr_addr_lo = &60      ; screen address (low byte) - calc_screen_addr result
scr_addr_hi = &61      ; screen address (high byte)
                       ; &62-&63 free
cat_px_x    = &64      ; caterpillar pixel X (0-159)
cat_px_y    = &65      ; caterpillar pixel Y (0-255)
anim_frame  = &66      ; animation frame counter
move_timer  = &67      ; movement speed divider (counts frames between moves)
sprite_drawn = &68     ; 1 if sprite is currently on screen (save buffer valid)
prev_scr_lo  = &69     ; previous sprite screen address lo
prev_scr_hi  = &6A     ; previous sprite screen address hi
prev_scanline = &6B    ; previous sprite starting scanline (py AND 7)
scroll_py     = &6C    ; hardware scroll offset in pixels (0-255, wraps)
item_buf_wr    = &6D    ; item ring buffer write index (0-23)
prev_scroll_py = &6E   ; scroll_py at last head draw (for change detection)
acorn_word  = &9C      ; bitmask of collected ACORN letters (bits 0-4) - must be &90+ to survive BASIC

; Season/map variables
map_ptr_lo   = &70     ; pointer to current map row data (low)
map_ptr_hi   = &71     ; pointer to current map row data (high)
map_row_idx  = &72     ; current row index (0..map_rows-1)
season       = &73     ; current season (0-3)

score_lo    = &74      ; current score (low byte)
score_hi    = &75      ; current score (high byte)
hiscore_lo  = &76      ; high score (low byte)
hiscore_hi  = &77      ; high score (high byte)
acorn_score = &78      ; incrementing acorn value (10, 20, 30, ...)
map_cycle   = &79      ; current map cycle within season (0-5, advances season at 6)
temp0       = &7A      ; general temp
temp1       = &7B      ; general temp
temp2       = &7C      ; general temp
temp3       = &7D      ; general temp
; &7E-&7F free (was mask_ptr for AND/OR blit, removed — black background)
osword_blk  = &80      ; OSWORD parameter block (&80-&8F)
scroll_div   = &90     ; frames between scrolls (4/3/2/1)
scroll_count = &91     ; countdown to next scroll event
season_rows  = &92     ; rows in current map (e.g. 64)
map_base_lo  = &93     ; base address of current map (for wrap)
map_base_hi  = &94     ; base address of current map (for wrap)
                       ; &95 free
body_count   = &96     ; number of body segments in ring buffer (0..BODY_MAX)
body_wridx   = &97     ; ring buffer write index (next slot to write)
body_rdidx   = &98     ; ring buffer read index (oldest slot)
copy_ptr_lo  = &99     ; pointer for body save buffer access (low)
copy_ptr_hi  = &9A     ; pointer for body save buffer access (high)
acorn_col_idx = &9B    ; rotating index into acorn_col_table (0-3)
item_buf_rd    = &6F    ; item ring buffer read index (0-23)
bonus_phase   = &9D    ; 0=normal play, 1=bonus round (empty+acorns after completion)
transition_phase = &9E ; 0=normal play, 1=transitioning between seasons (empty map + name)
game_result   = &9F    ; return code: 0=crash, 1=completed

; --- Constants ---
; Pixel coordinate boundaries for caterpillar movement
PX_LEFT_BOUND  = 25     ; minimum X pixel (left edge of playfield)
PX_RIGHT_BOUND = 134    ; maximum X pixel (right edge, sprite is 8+1px wide)
PX_CAT_INIT_X  = 76     ; starting X pixel position (must be even for 2px movement)
PX_CAT_INIT_Y  = 192    ; starting Y pixel position (row 24 = 8th from bottom)
MOVE_ACCUM     = 164    ; fractional speed: 164/256 * 50Hz ≈ 32px/sec
BODY_MAX       = 5      ; max body segments in ring buffer (eviction at row 30)

; ============================================================================
; Program starts at &1900 (standard location for BBC Micro programs)
; ============================================================================
ORG &1900
GUARD &3000

.start
    ; Save stack pointer for clean return to BASIC
    TSX
    STX saved_sp
    JMP game_init

; --- Fixed-address data (immediately after JMP, never executed) ---
; &1907 = saved_sp, &1908 = saved_acorn_word
; BASIC reads ?&1908 for acorn_word — address won't shift with code changes
.saved_sp
    EQUB 0
.saved_acorn_word
    EQUB 0

; ============================================================================
; Section: Return to BASIC
; ============================================================================
.return_to_basic
    LDA acorn_word
    STA saved_acorn_word  ; copy to non-ZP storage before BASIC can corrupt it
    LDX saved_sp
    TXS               ; restore stack pointer (clean regardless of call depth)
    RTS               ; returns to BASIC's CALL

; ============================================================================
; Section: Game initialisation (equivalent to lines 50-200)
; ============================================================================
.game_init
    ; *FX200,3 - disable escape key
    LDA #200
    LDX #3
    JSR OSBYTE

    ; Pre-clear MODE 2 screen memory (&3000-&7BFF) so mode switch
    ; doesn't flash garbage. Skip &7C00+ (current MODE 7 screen).
    LDA #0
    TAY
    LDX #&30
    STY &80 : STX &81        ; pointer = &3000
.clear_scr
    STA (&80),Y
    INY
    BNE clear_scr
    INC &81
    LDX &81
    CPX #&7C
    BNE clear_scr

    ; Wait for vsync then switch mode (screen memory is now zeroed)
    JSR vsync_wait

    ; MODE 2 + disable cursor + VDU 5 (table-driven)
    LDX #LO(vdu_init_data)
    LDY #HI(vdu_init_data)
    LDA #13
    JSR send_vdu_seq

    ; Define sound envelope 1: gulp effect (descending pitch, quick decay)
    LDA #8
    LDX #LO(envelope_data)
    LDY #HI(envelope_data)
    JSR OSWORD

    ; Define sound envelope 2: acorn "ding" (rising then falling pitch)
    LDA #8
    LDX #LO(envelope2_data)
    LDY #HI(envelope2_data)
    JSR OSWORD

    ; Initialise caterpillar position in pixel coords
    LDA #PX_CAT_INIT_X
    STA cat_px_x
    LDA #PX_CAT_INIT_Y
    STA cat_px_y

    ; Zero game state: &66-&75 (skipping hiscore &76-&77)
    LDA #0
    LDX #(&75 - &66)
.zi_loop1
    STA &66,X
    DEX
    BPL zi_loop1
    ; Zero body/phase state: &95-&9E
    LDX #(&9E - &95)
.zi_loop2
    STA &95,X
    DEX
    BPL zi_loop2
    ; A is still 0 from loop
    STA acorn_score
    STA collision_key_prev
    LDA #1 : STA collision_on
    LDA #2 : STA scroll_div : STA scroll_count  ; initial scroll speed
    ; Initialize item ring buffer (24 slots, all empty)
    ; rd leads wr by 1 → 23-slot delay matches row 1 to caterpillar row 24
    LDA #&FF : LDX #23
.init_item_ring
    STA item_col,X
    DEX
    BPL init_item_ring
    LDA #0 : STA item_buf_wr
    LDA #1 : STA item_buf_rd
    JSR show_sprite_page ; diagnostic: display all sprites, wait for key
    JSR enter_transition ; show "Autumn", load empty transition map

; ============================================================================
; Section: Main Game Loop
; Variable-rate scroll driven by season config. Fast path does vsync + sprite.
; Slow path (every 4th frame) handles collision, sound, and input.
; ============================================================================
.game_loop
    ; Wait for 1 vsync (50Hz for smooth pixel movement)
    JSR vsync_wait

    ; Increment frame counter
    INC anim_frame

    ; PROCcaterpillar - runs every frame for smooth sprite movement
    JSR proc_caterpillar

    ; Variable-rate scroll: decrement countdown, scroll on zero
    DEC scroll_count
    BNE after_scroll
    ; Reset countdown from season's scroll divider
    LDA scroll_div
    STA scroll_count
    ; Draw the next map row and scroll (VDU 11 clears row 0)
    JSR draw_map_row
    ; Advance map pointer to next row, wrap at end
    INC map_row_idx
    LDA map_row_idx
    CMP season_rows
    BCC after_scroll
    ; Map reached end - determine what to do next
    LDA transition_phase
    BNE transition_done     ; transition complete -> load real map
    LDA bonus_phase
    BNE bonus_complete      ; bonus map done -> show completed
    ; Normal play: wrap to start of current map
    INC map_cycle
    LDA map_cycle
    CMP #6
    BEQ season_done
    LDA map_base_lo : STA map_ptr_lo
    LDA map_base_hi : STA map_ptr_hi
    LDA #0 : STA map_row_idx
    STA item_counter            ; reset skip counter for new cycle
    JMP after_scroll
.season_done
    INC season
    LDA season
    CMP #4
    BCS round_over
    JSR enter_transition
    JMP after_scroll
.transition_done
    LDA #0 : STA transition_phase
    LDA bonus_phase
    BNE load_bonus_map
    JSR load_season         ; load the real season map
    JMP after_scroll
.load_bonus_map
    LDA #LO(map_bonus) : STA map_ptr_lo : STA map_base_lo
    LDA #HI(map_bonus) : STA map_ptr_hi : STA map_base_hi
    LDA #0 : STA map_row_idx
    LDA #64 : STA season_rows   ; 32 acorn + 32 empty
    JMP after_scroll
.bonus_complete
    JMP show_completed
.after_scroll

    ; Gate remaining slow operations to every 4th frame (~12.5Hz)
    LDA anim_frame
    AND #3
    BNE skip_slow_path

    ; === Slow path (every 4th frame, ~12.5Hz) ===

    ; (Season transitions are now cycle-based, triggered at map wrap)
    ; Check C key toggle (INKEY -83) with edge detection
    LDA #129
    LDX #(256-83)
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BNE ck_not_pressed
    ; C is pressed - was it pressed last frame?
    LDA collision_key_prev
    BNE ck_done             ; already held, don't toggle again
    ; Key-down edge: toggle collision_on
    LDA collision_on
    EOR #1
    STA collision_on
    LDA #1
    STA collision_key_prev
    JMP ck_done
.ck_not_pressed
    LDA #0
    STA collision_key_prev
.ck_done
    ; Queue movement tick (channel 2, very quiet, ~12.5Hz walking rhythm)
    LDA #7
    LDX #LO(sound_tick)
    LDY #HI(sound_tick)
    JSR OSWORD

.skip_slow_path
    JMP game_loop

.round_over
    ; All 16 season acorns collected? (acorn_score increments by 10 each, 16×10=160)
    LDA acorn_score
    CMP #160
    BNE ro_no_acorn_bonus
    ; Add 2000 to score
    CLC
    LDA score_lo
    ADC #LO(2000)
    STA score_lo
    LDA score_hi
    ADC #HI(2000)
    STA score_hi
    ; Celebration sound
    LDA #7
    LDX #LO(sound_celebrate)
    LDY #HI(sound_celebrate)
    JSR OSWORD
.ro_no_acorn_bonus
    ; Enter bonus phase with transition
    LDA #1
    STA bonus_phase
    JSR enter_transition    ; show "Bonus", load empty map
    JMP game_loop

; ============================================================================
; Section: PROCcaterpillar
; Pixel-based movement with direct screen memory sprite drawing
; 2-pixel movement (always byte-aligned, no odd sprite needed)
; Speed: fractional accumulator, ~32px/sec at 50Hz
; ============================================================================
.proc_caterpillar
    ; Fractional speed accumulator: move on overflow
    CLC
    LDA move_timer
    ADC #MOVE_ACCUM
    STA move_timer
    LDA #0
    ADC #0
    STA temp3               ; temp3 = 1 if movement frame, 0 if not

    ; First frame: just draw, no erase/body needed
    LDA sprite_drawn
    BEQ pc_draw_head

    ; Check if scroll happened since last head draw
    LDA scroll_py
    CMP prev_scroll_py
    BNE pc_scroll

    ; === NO SCROLL ===
    LDA temp3
    BEQ pc_idle             ; no scroll + no movement: nothing to do
    ; Movement without scroll: erase old head, check keys, redraw
    LDA prev_scr_lo : STA scr_addr_lo
    LDA prev_scr_hi : STA scr_addr_hi
    LDA prev_scanline : STA temp0
    JSR restore_background
    JMP pc_check_keys

.pc_idle
    RTS

.pc_scroll
    ; === SCROLL HAPPENED ===
    ; Evict oldest body segment if ring buffer is full
    LDA body_count
    CMP #BODY_MAX
    BCC pc_no_evict
    JSR erase_oldest_body
.pc_no_evict
    ; Add current head position as body segment (saves its background)
    JSR add_body_segment
    ; If no movement, just redraw head at new scroll position
    LDA temp3
    BNE pc_check_keys
    JMP pc_draw_head

.pc_check_keys
    ; Check Z key (left): INKEY(-98)
    LDA #129
    LDX #(256-98)
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BNE pc_no_left
    LDA cat_px_x
    CMP #PX_LEFT_BOUND+2    ; must be > left bound + 1
    BCC pc_no_left
    DEC cat_px_x            ; move 2 pixels left
    DEC cat_px_x
.pc_no_left

    ; Check M key (right): INKEY(-102)
    LDA #129
    LDX #(256-102)
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BNE pc_no_right
    LDA cat_px_x
    CMP #PX_RIGHT_BOUND-1   ; must be < right bound - 1
    BCS pc_no_right
    INC cat_px_x            ; move 2 pixels right
    INC cat_px_x
.pc_no_right

.pc_draw_head
    ; Calculate scroll-aware screen address
    JSR prep_sprite_addr

    ; Save state for next frame's change detection
    LDA scr_addr_lo : STA prev_scr_lo
    LDA scr_addr_hi : STA prev_scr_hi
    LDA temp0 : STA prev_scanline
    LDA scroll_py : STA prev_scroll_py

    ; Save background under new position, check collision, then draw head
    JSR save_background
    JSR proc_checkhit       ; check BEFORE drawing (reads save_buffer)
    JSR prep_sprite_addr    ; recalc (save modifies scr_addr)
    JSR draw_sprite
    LDA #1
    STA sprite_drawn
    RTS

; ============================================================================
; Section: Body Trail Ring Buffer
; BODY_MAX segments tracked. On scroll, old head becomes body. When full,
; oldest segment is erased (at bottom of screen, row 31) before adding new.
; ============================================================================

; --- add_body_segment ---
; Copies save_buffer (40 bytes) into the body ring buffer at wridx,
; and stores the screen address/scanline for later restore.
; Entry: prev_scr_lo/hi, prev_scanline = position of the old head
.add_body_segment
    ; Store screen address and scanline for this body slot
    LDX body_wridx
    LDA prev_scr_lo
    STA body_scr_lo,X
    LDA prev_scr_hi
    STA body_scr_hi,X
    LDA prev_scanline
    STA body_scanln,X

    ; Set up copy_ptr to point to body_save_N (wridx * 32)
    ; Lookup from table for speed
    LDA body_buf_addr_lo,X
    STA copy_ptr_lo
    LDA body_buf_addr_hi,X
    STA copy_ptr_hi

    ; Copy 32 bytes from save_buffer to (copy_ptr)
    LDY #31
.abs_copy_loop
    LDA save_buffer,Y
    STA (copy_ptr_lo),Y
    DEY
    BPL abs_copy_loop

    ; Advance write index (ring buffer wrap)
    INX
    CPX #BODY_MAX
    BCC abs_no_wrap
    LDX #0
.abs_no_wrap
    STX body_wridx

    ; Increment count (capped at BODY_MAX)
    INC body_count
    RTS

; --- erase_oldest_body ---
; Restores background from the oldest body segment directly to screen.
; Uses (copy_ptr_lo),Y to read body save buffer, writes to screen via
; (scr_addr_lo),Y - same scanline advance logic as restore_background.
; Does NOT touch save_buffer (head's background).
.erase_oldest_body
    LDX body_rdidx

    ; Set up screen address from stored body position
    LDA body_scr_lo,X
    STA scr_addr_lo
    LDA body_scr_hi,X
    STA scr_addr_hi
    LDA body_scanln,X
    STA temp0

    ; Set up copy_ptr to the body's save buffer
    LDA body_buf_addr_lo,X
    STA copy_ptr_lo
    LDA body_buf_addr_hi,X
    STA copy_ptr_hi

    ; Restore 32 bytes (4 cols x 8 rows) to screen from body buffer
    ; Uses copy_ptr as sequential read pointer (advanced by 4 each row)
    ; Y is swapped between buffer offset (0-3) and screen offset (0,8,16,24)
    LDA #8
    STA temp1           ; row counter
.eob_row_loop
    ; Byte 0: buffer[0] -> screen+0
    LDY #0
    LDA (copy_ptr_lo),Y
    STA (scr_addr_lo),Y
    ; Byte 1: buffer[1] -> screen+8
    INY
    LDA (copy_ptr_lo),Y
    LDY #8
    STA (scr_addr_lo),Y
    ; Byte 2: buffer[2] -> screen+16
    LDY #2
    LDA (copy_ptr_lo),Y
    LDY #16
    STA (scr_addr_lo),Y
    ; Byte 3: buffer[3] -> screen+24
    LDY #3
    LDA (copy_ptr_lo),Y
    LDY #24
    STA (scr_addr_lo),Y
    ; Advance copy_ptr by 4
    CLC
    LDA copy_ptr_lo
    ADC #4
    STA copy_ptr_lo
    BCC eob_no_ptr_wrap
    INC copy_ptr_hi
.eob_no_ptr_wrap
    JSR advance_scanline
    DEC temp1
    BNE eob_row_loop

    ; Advance read index (ring buffer wrap)
    LDX body_rdidx
    INX
    CPX #BODY_MAX
    BCC eob_rd_no_wrap
    LDX #0
.eob_rd_no_wrap
    STX body_rdidx

    ; Decrement count
    DEC body_count
    RTS

; ============================================================================
; Section: Season/Map System
; ============================================================================

; --- load_season ---
; Load season config into zero-page variables
; Entry: season = 0-3
; Uses 8-byte config entries indexed by season * 8
.load_season
    LDA season
    ASL A
    ASL A
    ASL A               ; A = season * 8
    TAX
    LDA season_config,X
    STA map_ptr_lo
    STA map_base_lo
    LDA season_config+1,X
    STA map_ptr_hi
    STA map_base_hi
    LDA season_config+2,X
    STA season_rows
    LDA season_config+3,X
    STA scroll_div
    STA scroll_count    ; prime the countdown
    LDA season_config+6,X
    STA col_offset
    LDA season_config+7,X
    STA item_skip
    LDA #0
    STA map_row_idx
    STA item_counter     ; reset skip counter
    STA map_cycle        ; reset cycle counter for new season
    RTS

; --- enter_transition ---
; Enter season transition: 96 empty scroll rows (no map data needed)
; Season name is drawn by draw_map_row at row 32
.enter_transition
    LDA #1 : STA transition_phase
    LDA #0 : STA map_row_idx
    LDA #76 : STA season_rows   ; empty scrolling for transition
    RTS

; --- draw_season_name ---
; Print season/bonus name at top of screen during transition
; with 2 bonus acorns either side. Called from draw_map_row when
; transition_phase=1 and map_row_idx=32
.draw_season_name
    ; Determine name index: 0-3 for seasons, 4 for bonus
    LDX season
    LDA bonus_phase
    BEQ dsn_got_idx
    LDX #4
.dsn_got_idx
    STX temp0
    ; COLOUR 6 (cyan, same as caterpillar - no collision conflict)
    LDA #6
    JSR do_colour
    ; TAB(4, 1) - centred near top of screen
    LDA #4
    LDX #1 : JSR do_tab
    ; Print season name string
    LDX temp0
    LDA season_name_lo,X
    STA temp1
    LDA season_name_hi,X
    TAY
    LDX temp1
    JMP print_string      ; tail call

; --- check_acorn_letter ---
; Check if caterpillar is at the target ACORN letter column during transition.
; Called at map_row_idx=55 (when season name scrolls past caterpillar row).
.check_acorn_letter
    ; Get season/bonus index
    LDX season
    LDA bonus_phase
    BEQ cal_season
    LDX #4
.cal_season
    ; Already collected this letter?
    LDA acorn_word
    AND acorn_bit_table,X
    BNE cal_done
    ; Check column match: |cat_col - target_col| <= 1 (±1 tolerance)
    LDA cat_px_x
    LSR A : LSR A : LSR A
    SEC
    SBC acorn_target_col,X
    CLC
    ADC #1              ; map -1→0, 0→1, 1→2
    CMP #3
    BCS cal_done        ; >= 3 means diff was < -1 or > 1
    ; Collect letter!
    LDA acorn_word
    ORA acorn_bit_table,X
    STA acorn_word
    ; Erase letter from screen: name was at row 1 when map_row_idx=32
    ; Current screen row = map_row_idx - 31
    LDA acorn_target_col,X
    STA temp1               ; save target column
    LDA map_row_idx
    SEC
    SBC #31
    TAX                     ; X = screen row
    LDA temp1               ; A = column
    JSR do_tab
    LDA #32                 ; space character
    JSR OSWRCH
    ; Feedback: ding sound
    LDA #7
    LDX #LO(sound_letter)
    LDY #HI(sound_letter)
    JSR OSWORD
.cal_done
    RTS


; --- draw_map_row ---
; Draw items from current map row, then scroll screen
; Map format: item bytes until &FF terminator
;   &00-&13: mushroom at column N (2 chars wide)
;   &20-&33: item at column N-32
;   &40-&53: acorn at column N-64
;   &FF: end of row
.draw_map_row
    ; VDU 4 - text cursor mode (needed for row clear VDU 28/12)
    LDA #4
    JSR OSWRCH

    ; Default: no item this row (overwritten if mushroom/apple/acorn is drawn)
    LDX item_buf_wr
    LDA #&FF
    STA item_col,X

    ; During transition, skip item parsing (no map data to read)
    LDA transition_phase
    BEQ dmr_has_items
    ; Transition row: draw season name at row 32, check ACORN letter at rows 50-60
    LDA map_row_idx
    CMP #32
    BNE dmr_not_32
    JSR draw_season_name
    JMP dmr_no_name
.dmr_not_32
    CMP #50
    BCC dmr_skip_check
    CMP #61
    BCS dmr_skip_check
    JSR check_acorn_letter
.dmr_skip_check
    JMP dmr_no_name
.dmr_has_items

    ; Walk through map data (pair format: row, type_col)
    LDY #0
.dmr_loop
    LDA (map_ptr_lo),Y      ; peek at row number
    CMP map_row_idx
    BEQ dmr_row_match        ; row matches, parse items
    JMP dmr_done_items        ; not this row (or &FF sentinel)
.dmr_row_match
    INY
    LDA (map_ptr_lo),Y      ; type_col byte
    INY
    STY temp3

    STA temp2               ; save type_col before skip check clobbers A

    ; Acorns (&40+) bypass skip check AND column offset - fixed landmarks
    CMP #&40
    BCS dmr_no_offset

    ; Apples (&20+) bypass the skip check - always drawn
    CMP #&20
    BCS dmr_apply_offset

    ; --- Mushroom skip check (skip every Nth mushroom: 0=none, 2=every 2nd, 3=every 3rd) ---
    LDA item_skip
    BEQ dmr_apply_offset    ; 0 = no skipping, draw all
    INC item_counter
    LDA item_counter
    CMP item_skip
    BCC dmr_apply_offset    ; counter < skip -> draw this item
    LDA #0
    STA item_counter        ; reset counter, skip this item
    JMP dmr_next_item

.dmr_apply_offset
    ; --- Apply column offset ---
    LDA temp2               ; restore type_col
    AND #&1F                ; extract column (0-19)
    CLC
    ADC col_offset
    CMP #20
    BCC dmr_no_col_wrap
    SBC #20                 ; carry is set from CMP, so SBC #20 is correct
.dmr_no_col_wrap
    STA temp0               ; adjusted column
    LDA temp2
    AND #&60                ; type bits only
    ORA temp0               ; reconstruct type_col with new column
    STA temp2               ; write back so offset is used by drawing code

.dmr_no_offset
    ; Acorns arrive here with original type_col in temp2 (no offset applied)
    LDA temp2
    ; Determine item type
    CMP #&40
    BCC dmr_not_acorn   ; < &40: not acorn
    JMP dmr_acorn
.dmr_not_acorn
    CMP #&20
    BCS dmr_item       ; >= &20: apple
    ; Fall through: mushroom (&00-&13)

    ; --- Mushroom (direct screen write: cap_left + cap_right at row 1, stem at row 2) ---
    STA temp0           ; column
    ; Cap left at (col, row 1)
    LDX #1
    JSR calc_item_addr
    LDA #LO(spr_cap_left) : STA copy_ptr_lo
    LDA #HI(spr_cap_left) : STA copy_ptr_hi
    JSR draw_item
    ; Cap right at (col+1, row 1)
    LDA temp0
    CLC : ADC #1
    LDX #1
    JSR calc_item_addr
    LDA #LO(spr_cap_right) : STA copy_ptr_lo
    LDA #HI(spr_cap_right) : STA copy_ptr_hi
    JSR draw_item
    ; Stem at (col, row 2)
    LDA temp0
    LDX #2
    JSR calc_item_addr
    LDA #LO(spr_stem) : STA copy_ptr_lo
    LDA #HI(spr_stem) : STA copy_ptr_hi
    JSR draw_item
    ; Register mushroom cap in ring buffer (temp0 = left column, preserved by draw_item)
    LDX item_buf_wr
    LDA temp0 : STA item_col,X
    LDA #0 : STA item_type,X   ; type 0 = mushroom
    ; Stem at row 2 arrives 1 scroll before cap at row 1. Register stem
    ; collision in previous ring buffer slot (if empty) so it's checked
    ; when the stem reaches caterpillar row, not just the cap.
    DEX : BPL stem_no_wrap : LDX #23
.stem_no_wrap
    LDA item_col,X
    CMP #&FF                    ; previous slot unused?
    BNE stem_skip
    LDA temp0 : STA item_col,X ; same column as cap left
    LDA #3 : STA item_type,X   ; type 3 = stem (1-col wide crash check)
.stem_skip
    JMP dmr_next_item

.dmr_item
    ; Item: column = byte - &20 (direct screen write, sprite varies by season)
    SEC
    SBC #&20
    STA temp0           ; column
    ; Register item in ring buffer
    LDX item_buf_wr
    STA item_col,X      ; A still has column
    LDA #1 : STA item_type,X   ; type 1 = item
    LDA temp0
    LDX #1
    JSR calc_item_addr
    LDX season
    LDA item_spr_lo,X : STA copy_ptr_lo
    LDA item_spr_hi,X : STA copy_ptr_hi
    JSR draw_item
    JMP dmr_next_item

.dmr_acorn
    ; Pick column from rotating table (varies each map cycle)
    LDX acorn_col_idx
    LDA acorn_col_table,X
    STA temp0
    INX
    CPX #4
    BCC dmr_acorn_no_wrap
    LDX #0
.dmr_acorn_no_wrap
    STX acorn_col_idx
    ; Register acorn in ring buffer
    LDX item_buf_wr
    LDA temp0 : STA item_col,X
    LDA #2 : STA item_type,X   ; type 2 = acorn
    ; Acorn top at (col, row 1) — direct screen write
    LDA temp0
    LDX #1
    JSR calc_item_addr
    LDA #LO(spr_acorn_top) : STA copy_ptr_lo
    LDA #HI(spr_acorn_top) : STA copy_ptr_hi
    JSR draw_item
    ; Acorn bottom at (col, row 2)
    LDA temp0
    LDX #2
    JSR calc_item_addr
    LDA #LO(spr_acorn_bottom) : STA copy_ptr_lo
    LDA #HI(spr_acorn_bottom) : STA copy_ptr_hi
    JSR draw_item

.dmr_next_item
    LDY temp3           ; restore map index
    JMP dmr_loop

.dmr_done_items
    ; Advance map_ptr by Y (bytes consumed: 2 per item, 0 if empty row)
    TYA
    CLC
    ADC map_ptr_lo
    STA map_ptr_lo
    LDA map_ptr_hi
    ADC #0
    STA map_ptr_hi

.dmr_no_name

    ; Clear row 30 before scroll (table-driven)
    LDX #LO(vdu_row_clear)
    LDY #HI(vdu_row_clear)
    LDA #7
    JSR send_vdu_seq

    ; VDU 30 : VDU 11 - home cursor then cursor up (triggers hardware scroll)
    ; VDU 11 effect is also used in my original game and cause the body ripple effect
    LDA #30
    JSR OSWRCH
    LDA #11
    JSR OSWRCH

    ; Track the hardware scroll offset (8 pixels per scroll)
    CLC
    LDA scroll_py
    ADC #8
    STA scroll_py

    ; Advance item ring buffer pointers (both move 1 slot per scroll)
    LDX item_buf_wr
    INX
    CPX #24
    BCC ibw_no_wrap
    LDX #0
.ibw_no_wrap
    STX item_buf_wr
    LDX item_buf_rd
    INX
    CPX #24
    BCC ibr_no_wrap
    LDX #0
.ibr_no_wrap
    STX item_buf_rd

    ; VDU 5 - graphics cursor mode
    LDA #5
    JMP OSWRCH

; ============================================================================
; Section: PROCcheckhit - ring buffer position-based collision detection
; Checks the item at the current read index against caterpillar's text column
; range. Items are registered during draw_map_row and arrive at caterpillar
; row 24 exactly 23 scrolls later (matching the ring buffer delay).
; Type dispatch: 0=mushroom→crash, 1=item→score by season, 2=acorn→bonus, 3=stem→crash.
; Called from proc_caterpillar after save_background, before draw_sprite.
; ============================================================================
.proc_checkhit
    ; Skip collision check if toggled off
    LDA collision_on
    BNE pch_active
    RTS
.pch_active
    ; Read item at current ring buffer position
    LDX item_buf_rd
    LDA item_col,X
    CMP #&FF
    BNE pch_has_item
    RTS                     ; &FF = no item at this row
.pch_has_item
    STA temp0               ; item column (left edge)
    LDA item_type,X
    STA temp1               ; item type (0=mushroom, 1=item, 2=acorn, 3=stem)
    ; Calculate caterpillar text column range
    LDA cat_px_x
    LSR A : LSR A : LSR A   ; cat_left_col = px / 8
    STA temp2
    LDA cat_px_x
    CLC : ADC #7
    LSR A : LSR A : LSR A   ; cat_right_col = (px + 7) / 8
    STA temp3
    ; Determine item's right edge (mushroom = 2 cols, others = 1 col)
    LDA temp1
    BNE pch_single_col      ; type 1 or 2 = 1 column wide
    ; Mushroom: occupies [col, col+1]
    LDA temp0
    CLC : ADC #1
    JMP pch_check_overlap
.pch_single_col
    LDA temp0               ; right_edge = col (same as left)
.pch_check_overlap
    ; A = item right edge. Check range overlap:
    ; hit if right_edge >= cat_left AND cat_right >= item_left
    CMP temp2               ; right_edge vs cat_left_col
    BCC pch_miss            ; right_edge < cat_left → miss
    LDA temp3               ; cat_right_col
    CMP temp0               ; vs item_left_col
    BCC pch_miss            ; cat_right < item_left → miss
    ; === HIT! ===
    ; Clear ring buffer slot (prevent re-triggering)
    LDX item_buf_rd
    LDA #&FF : STA item_col,X
    ; Dispatch mushroom/stem early — they stay visible (no erase) for debug
    LDA temp1
    BEQ pch_mushroom             ; type 0 = cap → crash (skip erase)
    CMP #3
    BEQ pch_mushroom             ; type 3 = stem → crash (skip erase)
    ; Food items: erase from screen on contact
    ; Zero save_buffer so background restore writes black (erases item)
    PHA                          ; save item type
    LDA #0 : LDX #31
.pch_clear_sb
    STA save_buffer,X
    DEX
    BPL pch_clear_sb
    ; Clear item from screen: 2 spaces at caterpillar row
    LDA #4 : JSR OSWRCH          ; VDU 4
    LDA #0 : JSR do_colour       ; black text
    LDA cat_px_x
    LSR A : LSR A : LSR A
    LDX #24
    JSR do_tab
    LDA #32 : JSR OSWRCH         ; space 1
    LDA #32 : JSR OSWRCH         ; space 2
    LDA #5 : JSR OSWRCH          ; VDU 5
    PLA                          ; restore item type
    CMP #2
    BEQ pch_acorn                ; type 2 = acorn → bonus scoring
    ; Type 1 = item: score and sound vary by season
    LDX season
    LDA item_points,X          ; A = points for this season
    PHA                          ; save points on stack
    LDA item_sound_hi,X
    TAY                          ; Y = sound block hi
    LDA item_sound_lo,X
    TAX                          ; X = sound block lo
    PLA                          ; A = points
    JMP add_score_and_sound
.pch_mushroom
    JMP proc_crash
.pch_acorn
    LDA acorn_score : CLC : ADC #10 : STA acorn_score
    LDX #LO(sound_hit5) : LDY #HI(sound_hit5)
    JMP add_score_and_sound
.pch_miss
    RTS

; Common score addition + sound routine
; Entry: X/Y = sound block address, A = points to add
.add_score_and_sound
    PHA                 ; save points
    ; Hit-stop: freeze 2 frames for kinetic "gulp" feel
    STX temp0 : STY temp1
    JSR vsync_wait
    JSR vsync_wait
    LDX temp0 : LDY temp1
    ; Play sound
    LDA #7
    JSR OSWORD          ; X/Y restored
    ; Add points to score
    PLA
    CLC
    ADC score_lo
    STA score_lo
    LDA score_hi
    ADC #0
    STA score_hi
    RTS

; ============================================================================
; Section: PROCcrash
; ============================================================================
.proc_crash
    ; SOUND 0,amp,4,1 with amp from -15..-1
    ; Build constant parts of OSWORD 7 block once
    LDA #0
    STA osword_blk       ; channel lo
    STA osword_blk+1     ; channel hi
    STA osword_blk+5     ; pitch hi
    STA osword_blk+7     ; duration hi
    LDA #&FF
    STA osword_blk+3     ; amplitude hi (sign extend)
    LDA #4
    STA osword_blk+4     ; pitch lo
    LDA #1
    STA osword_blk+6     ; duration lo

    ; Loop amplitude -15 (&F1) to -1 (&FF)
    LDA #&F1
.crash_loop
    STA osword_blk+2     ; amplitude lo (only changing field)
    LDA #7
    LDX #LO(osword_blk)
    LDY #HI(osword_blk)
    JSR OSWORD
    JSR vsync_wait
    LDA osword_blk+2
    CLC : ADC #1
    BNE crash_loop       ; Z flag set by ADC when &FF wraps to 0

    ; *FX15,0 - flush all buffers
    LDA #15
    LDX #0
    JSR OSBYTE

    ; Pause so player can see where collision occurred
    JSR OSRDCH               ; wait for any key press

    ; IF S% > T% THEN T% = S% (update hiscore)
    ; Compare score with high score
    LDA hiscore_lo
    CMP score_lo
    LDA hiscore_hi
    SBC score_hi
    BCS no_new_hiscore  ; hiscore >= score
    ; New high score
    LDA score_lo
    STA hiscore_lo
    LDA score_hi
    STA hiscore_hi
.no_new_hiscore

    ; Return to BASIC with result code 0 (crash)
    LDA #0
    STA game_result
    JMP return_to_basic

; ============================================================================
; Section: Completion (all 4 seasons cleared)
; ============================================================================
.show_completed
    ; ACORN bonus: if all 5 letters collected, add 1000 points
    LDA acorn_word
    CMP #&1F          ; all 5 bits set?
    BNE sc_no_acorn
    CLC
    LDA score_lo
    ADC #LO(1000)
    STA score_lo
    LDA score_hi
    ADC #HI(1000)
    STA score_hi
.sc_no_acorn
    ; Update high score if needed
    LDA hiscore_lo
    CMP score_lo
    LDA hiscore_hi
    SBC score_hi
    BCS sc_no_hiscore
    LDA score_lo : STA hiscore_lo
    LDA score_hi : STA hiscore_hi
.sc_no_hiscore
    ; Return to BASIC with result code 1 (completed)
    LDA #1
    STA game_result
    JMP return_to_basic

; ============================================================================
; Section: Helper Subroutines
; ============================================================================

; --- do_colour ---
; VDU 17,A - set text colour
; Entry: A=colour
.do_colour
    PHA
    LDA #17 : JSR OSWRCH
    PLA     : JMP OSWRCH

; --- do_tab ---
; VDU 31,A,X - TAB(A,X)
; Entry: A=column, X=row
.do_tab
    PHA
    LDA #31 : JSR OSWRCH
    PLA     : JSR OSWRCH
    TXA     : JMP OSWRCH

; --- send_vdu_seq ---
; Send A bytes from table at X/Y via OSWRCH
; Entry: X=lo, Y=hi of data, A=byte count
.send_vdu_seq
    STX temp0
    STY temp1
    STA temp2
    LDY #0
.svs_loop
    LDA (temp0),Y
    JSR OSWRCH
    INY
    CPY temp2
    BNE svs_loop
    RTS

; --- vsync_wait ---
; Wait for vertical sync (OSBYTE 19)
.vsync_wait
    LDA #19
    JMP OSBYTE

; --- print_string ---
; Print null-terminated string
; Entry: X=lo, Y=hi of string address
.print_string
    STX temp0
    STY temp1
    LDY #0
.ps_loop
    LDA (temp0),Y
    BEQ ps_done
    JSR OSWRCH
    INY
    BNE ps_loop         ; max 256 chars per string
.ps_done
    RTS

; --- advance_scanline ---
; Advance scr_addr to next scanline, handling char row boundary (+633)
; and screen memory wrap (&8000 -> &3000)
; Entry/Exit: scr_addr_lo/hi, temp0 (scanline within char row)
.advance_scanline
    INC temp0
    LDA temp0
    AND #7
    STA temp0
    BNE as_same_row
    ; Crossed char row boundary: add 633
    CLC
    LDA scr_addr_lo
    ADC #LO(633)
    STA scr_addr_lo
    LDA scr_addr_hi
    ADC #HI(633)
    STA scr_addr_hi
    CMP #&80
    BCC as_done
    SEC
    SBC #&50
    STA scr_addr_hi
    RTS
.as_same_row
    INC scr_addr_lo
    BNE as_done
    INC scr_addr_hi
.as_done
    RTS

; --- calc_item_addr ---
; Calculate screen address for a text cell, accounting for hardware scroll.
; Items are always char-aligned (scroll_py is multiples of 8), so scanline=0.
; Entry: A = text column (0-19), X = text row (1-2)
; Result: scr_addr_lo/hi = screen address of top-left byte
; Clobbers: A, X, Y
.calc_item_addr
    PHA                 ; save text_col
    ; Physical char row = ((text_row * 8) - scroll_py) / 8
    TXA
    ASL A : ASL A : ASL A  ; A = text_row * 8
    SEC
    SBC scroll_py       ; physical pixel Y (wraps via byte truncation)
    LSR A : LSR A : LSR A  ; physical char row (0-31)
    TAX
    LDA row_table_lo,X
    STA scr_addr_lo
    LDA row_table_hi,X
    STA scr_addr_hi
    ; Add text_col * 32 (each text column = 4 byte-cols * 8 bytes)
    PLA                 ; restore text_col (0-19)
    TAX                 ; save copy in X
    ; High byte: text_col >> 3 (0, 1, or 2)
    LSR A : LSR A : LSR A
    CLC
    ADC scr_addr_hi
    STA scr_addr_hi
    ; Low byte: (text_col AND 7) << 5
    TXA
    AND #7
    ASL A : ASL A : ASL A : ASL A : ASL A
    CLC
    ADC scr_addr_lo
    STA scr_addr_lo
    BCC cia_no_carry
    INC scr_addr_hi
.cia_no_carry
    RTS

; --- draw_item ---
; Write 32 bytes of pre-encoded sprite data to screen (4 byte-cols x 8 scanlines).
; Items are char-aligned so scanline advance is always +1 (no row boundary cross).
; Entry: copy_ptr_lo/hi = sprite data address, scr_addr_lo/hi = screen address
; Clobbers: A, Y, temp1 (preserves temp0)
.draw_item
    LDA #8
    STA temp1           ; row counter
.di_row_loop
    ; Write 4 bytes at screen offsets 0, 8, 16, 24
    LDY #0
    LDA (copy_ptr_lo),Y
    STA (scr_addr_lo),Y
    INY
    LDA (copy_ptr_lo),Y
    LDY #8
    STA (scr_addr_lo),Y
    LDY #2
    LDA (copy_ptr_lo),Y
    LDY #16
    STA (scr_addr_lo),Y
    LDY #3
    LDA (copy_ptr_lo),Y
    LDY #24
    STA (scr_addr_lo),Y
    ; Advance copy_ptr by 4 (next scanline of sprite data)
    CLC
    LDA copy_ptr_lo
    ADC #4
    STA copy_ptr_lo
    BCC di_no_ptr_carry
    INC copy_ptr_hi
.di_no_ptr_carry
    ; Advance scanline (+1, always within same char row)
    INC scr_addr_lo
    BNE di_no_scr_carry
    INC scr_addr_hi
.di_no_scr_carry
    DEC temp1
    BNE di_row_loop
    RTS


; ============================================================================
; Section: Screen Address Routines
; ============================================================================

; --- prep_sprite_addr ---
; Calculate screen address and starting scanline from pixel coords
; Accounts for hardware scroll offset (scroll_py)
; Entry: cat_px_x, cat_px_y already set
; Result: scr_addr_lo/hi, temp0 (starting scanline)
.prep_sprite_addr
    ; Physical Y = (visual_py - scroll_py) AND &FF
    ; Subtract because screen scroll DOWN decreases CRTC display start
    SEC
    LDA cat_px_y
    SBC scroll_py
    STA temp2           ; physical Y for calc_screen_addr
    JSR calc_screen_addr
    LDA temp2
    AND #7
    STA temp0           ; starting scanline
    RTS

; --- calc_screen_addr ---
; Calculate MODE 2 screen address from pixel coordinates
; Entry: cat_px_x = pixel X (0-159), cat_px_y = pixel Y (0-255)
; Result: scr_addr_lo/hi = screen address
;
; MODE 2 memory: 80 CRTC character cells per row, each 8 bytes (8 scanlines).
; addr = &3000 + (py >> 3) * 640 + (px >> 1) * 8 + (py AND 7)
;
; Adjacent byte-columns are 8 bytes apart in memory (character-cell interleaved).
; An 8-pixel-wide sprite spans 4 byte-columns at stride 8.

.calc_screen_addr
    ; Entry: temp2 = physical pixel Y, cat_px_x = pixel X
    ; Result: scr_addr_lo/hi = screen address
    ; Step 1: row base from lookup table
    LDA temp2
    LSR A
    LSR A
    LSR A               ; A = char_row (0-31)
    TAX
    LDA row_table_lo,X
    STA scr_addr_lo
    LDA row_table_hi,X
    STA scr_addr_hi

    ; Step 2: add byte_col * 8 (16-bit, max 79*8=632)
    LDA cat_px_x
    LSR A               ; byte_col = px / 2 (0-79)
    STA temp0           ; save byte_col for high byte calc
    ASL A
    ASL A
    ASL A               ; low byte of byte_col * 8 (overflow into carry)
    CLC
    ADC scr_addr_lo
    STA scr_addr_lo
    LDA scr_addr_hi
    ADC #0
    STA scr_addr_hi
    ; Add high byte: byte_col >> 5 (0, 1, or 2)
    LDA temp0
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    CLC
    ADC scr_addr_hi
    STA scr_addr_hi

    ; Step 3: add scanline = py AND 7
    LDA temp2
    AND #7
    CLC
    ADC scr_addr_lo
    STA scr_addr_lo
    LDA scr_addr_hi
    ADC #0
    STA scr_addr_hi

    RTS

; --- save_background ---
; Save 4 byte-columns (32 bytes) of screen data into save_buffer
; Sprite is always even-aligned (2px movement), so 4 cols covers the full 8px width
; Entry: scr_addr_lo/hi = top-left screen address
;        temp0 = starting scanline (py AND 7)
; Clobbers: A, X, Y, temp0, temp1
.save_background
    LDX #0              ; buffer index
    LDA #8              ; row counter
    STA temp1
.sb_row_loop
    ; Read 4 bytes at offsets 0, 8, 16, 24
    LDY #0
    LDA (scr_addr_lo),Y
    STA save_buffer,X
    INX
    LDY #8
    LDA (scr_addr_lo),Y
    STA save_buffer,X
    INX
    LDY #16
    LDA (scr_addr_lo),Y
    STA save_buffer,X
    INX
    LDY #24
    LDA (scr_addr_lo),Y
    STA save_buffer,X
    INX
    JSR advance_scanline
    DEC temp1
    BNE sb_row_loop
    RTS

; --- restore_background ---
; Restore 4 byte-columns (32 bytes) from save_buffer to screen
; Entry: scr_addr_lo/hi = top-left screen address (same as when saved)
;        temp0 = starting scanline (py AND 7)
; Clobbers: A, X, Y, temp0, temp1
.restore_background
    LDX #0
    LDA #8
    STA temp1
.rb_row_loop
    LDY #0
    LDA save_buffer,X
    STA (scr_addr_lo),Y
    INX
    LDY #8
    LDA save_buffer,X
    STA (scr_addr_lo),Y
    INX
    LDY #16
    LDA save_buffer,X
    STA (scr_addr_lo),Y
    INX
    LDY #24
    LDA save_buffer,X
    STA (scr_addr_lo),Y
    INX
    JSR advance_scanline
    DEC temp1
    BNE rb_row_loop
    RTS

; --- draw_sprite ---
; Draw 8x8 sprite (always even-aligned with 2px movement)
; Entry: scr_addr_lo/hi = top-left screen address
;        temp0 = starting scanline (py AND 7)
; Clobbers: A, X, Y, temp0, temp1
.draw_sprite

; --- draw_sprite_even ---
; Even pixel position: 4 bytes/row, full overwrite
.draw_sprite_even
    LDX #0              ; sprite data index
    LDA #8
    STA temp1           ; row counter
.de_row_loop
    LDY #0
    LDA spr_caterpillar,X
    STA (scr_addr_lo),Y
    INX
    LDY #8
    LDA spr_caterpillar,X
    STA (scr_addr_lo),Y
    INX
    LDY #16
    LDA spr_caterpillar,X
    STA (scr_addr_lo),Y
    INX
    LDY #24
    LDA spr_caterpillar,X
    STA (scr_addr_lo),Y
    INX
    JSR advance_scanline
    DEC temp1
    BNE de_row_loop
    RTS


; ============================================================================
; Section: Data Tables
; ============================================================================

; --- VDU sequence data ---
.vdu_init_data     ; MODE 2 + cursor off + VDU 5
    EQUB 22, 2, 23, 0, 10, 32, 0, 0, 0, 0, 0, 0, 5
.vdu_row_clear     ; VDU 28,0,30,19,30 + CLS + restore window
    EQUB 28, 0, 30, 19, 30, 12, 26

; saved_sp and saved_acorn_word are at fixed addresses &1907/&1908 (after JMP in entry sequence)

; --- Collision toggle (C key) ---
.collision_on
    EQUB 1              ; 1=collision active, 0=disabled
.collision_key_prev
    EQUB 0              ; previous C key state (for edge detection)

; --- Map compression variables ---
.col_offset       EQUB 0   ; column offset for current season (0-19)
.item_skip        EQUB 0   ; skip every Nth mushroom (0=none, 2=every 2nd, 3=every 3rd)
.item_counter     EQUB 0   ; counts up, resets at item_skip (skip that mushroom)

; --- Sprite save buffer (32 bytes for 4 byte-columns x 8 rows) ---
.save_buffer
    SKIP 32

; --- Body ring buffer data ---
; Screen address and scanline for each body segment (5 slots)
.body_scr_lo
    SKIP BODY_MAX
.body_scr_hi
    SKIP BODY_MAX
.body_scanln
    SKIP BODY_MAX

; Save buffers for body segments (32 bytes each, 5 slots = 160 bytes)
.body_save_0
    SKIP 32
.body_save_1
    SKIP 32
.body_save_2
    SKIP 32
.body_save_3
    SKIP 32
.body_save_4
    SKIP 32

; --- Item ring buffer data (24 entries each) ---
; Tracks items from row 1 draw position to caterpillar row 24.
; Each slot holds the text column (&FF = empty) and type (0/1/2).
.item_col
    SKIP 24
.item_type
    SKIP 24

; Lookup tables: address of each body save buffer (lo/hi)
.body_buf_addr_lo
    EQUB LO(body_save_0)
    EQUB LO(body_save_1)
    EQUB LO(body_save_2)
    EQUB LO(body_save_3)
    EQUB LO(body_save_4)
.body_buf_addr_hi
    EQUB HI(body_save_0)
    EQUB HI(body_save_1)
    EQUB HI(body_save_2)
    EQUB HI(body_save_3)
    EQUB HI(body_save_4)

.spr_caterpillar
    EQUB &2A, &01, &02, &15
    EQUB &04, &01, &02, &08
    EQUB &00, &01, &02, &00
    EQUB &0F, &01, &02, &0F
    EQUB &04, &01, &02, &08
    EQUB &0F, &01, &02, &0F
    EQUB &04, &01, &02, &08
    EQUB &0F, &01, &02, &0F

; --- MODE 2 row address lookup table ---
; row_table[n] = &3000 + n * 640
; 32 entries (char rows 0-31)
.row_table_lo
FOR i, 0, 31
    EQUB LO(&3000 + i*640)
NEXT

.row_table_hi
FOR i, 0, 31
    EQUB HI(&3000 + i*640)
NEXT

.spr_cap_left
    EQUB &00,&00,&00,&00
    EQUB &00,&00,&00,&0C
    EQUB &00,&00,&0C,&0C
    EQUB &00,&0C,&0C,&0C
    EQUB &00,&0C,&1C,&0C
    EQUB &04,&0C,&0C,&0C
    EQUB &0C,&1C,&0C,&0C
    EQUB &0C,&0C,&0C,&0C

.spr_cap_right
    EQUB &00,&00,&00,&00
    EQUB &00,&00,&00,&00
    EQUB &0C,&00,&00,&00
    EQUB &0C,&08,&00,&00
    EQUB &0C,&0C,&00,&00
    EQUB &1C,&0C,&00,&00
    EQUB &0C,&0C,&08,&00
    EQUB &0C,&0C,&08,&00

.spr_stem
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&05,&3F
    EQUB &00,&00,&00,$00

.spr_leaf
    EQUB &02,&00,&00,&00
    EQUB &01,&07,&00,&00
    EQUB &13,&27,&02,&00
    EQUB &13,&33,&1F,&00
    EQUB &13,&33,&1B,&02
    EQUB &13,&13,&27,&02
    EQUB &01,&13,&13,&23
    EQUB &00,&13,&13,&13

.spr_snow
    EQUB &00,&55,&00,&00
    EQUB &00,&2A,&2A,&00
    EQUB &15,&15,&15,&00
    EQUB &AA,&3F,&2A,&AA
    EQUB &15,&15,&15,&00
    EQUB &00,&2A,&2A,&00
    EQUB &00,&55,&00,&00
    EQUB &00,&00,&00,&00

.spr_flower
    EQUB &00,&33,&33,&00
    EQUB &11,&37,&3B,&22
    EQUB &33,&3B,&37,&33
    EQUB &33,&37,&3B,&33
    EQUB &11,&33,&33,&22
    EQUB &11,&33,&33,&22
    EQUB &00,&04,&08,&00
    EQUB &00,&04,&08,&00

.spr_acorn_top
    EQUB &00,&C3,&C3,&00
    EQUB &41,&CF,&DF,&82
    EQUB &C7,&CF,&EF,&CF
    EQUB &C7,&CF,&CF,&CF
    EQUB &C7,&CF,&CF,&CF
    EQUB &C7,&CF,&CF,&CF
    EQUB &CF,&CF,&CF,&CF
    EQUB &CF,&CF,&CF,&CF

.spr_acorn_bottom
    EQUB &00,&00,&00,&00
    EQUB &0C,&0C,&0C,&0C
    EQUB &0C,&0C,&0C,&0C
    EQUB &04,&0C,&0C,&08
    EQUB &00,&0C,&0C,&00
    EQUB &00,&04,&08,&00
    EQUB &00,&04,&08,&00
    EQUB &04,&0C,&00,&00

.spr_apple
    EQUB &00,&0C,&00,&00
    EQUB &01,&0C,&02,&00
    EQUB &03,&2B,&03,&00
    EQUB &03,&03,&03,&00
    EQUB &03,&03,&03,&00
    EQUB &03,&03,&03,&00
    EQUB &01,&03,&02,&00
    EQUB &00,&00,&00,&00

; --- Item sprite lookup table (indexed by season 0-3) ---
.item_spr_lo
    EQUB LO(spr_leaf), LO(spr_snow), LO(spr_flower), LO(spr_apple)
.item_spr_hi
    EQUB HI(spr_leaf), HI(spr_snow), HI(spr_flower), HI(spr_apple)


; --- Item scoring lookup tables (indexed by season 0-3) ---
; Points awarded and sound block played when eating an item
.item_points
    EQUB 5, 10, 15, 20       ; autumn=5, winter=10, spring=15, summer=20
.item_sound_lo
    EQUB LO(sound_hit1), LO(sound_hit2), LO(sound_hit3), LO(sound_hit4)
.item_sound_hi
    EQUB HI(sound_hit1), HI(sound_hit2), HI(sound_hit3), HI(sound_hit4)

; --- Sound data blocks (8 bytes each) ---
; Format: channel(2), amplitude(2), pitch(2), duration(2)

; Eat sounds use envelope 1 (gulp: descending pitch, quick decay)
; Autumn leaf (5pts): SOUND 1,1,60,4
.sound_hit1
    EQUW 1, 1, 60, 4

; Winter snow (10pts): SOUND 1,1,80,4
.sound_hit2
    EQUW 1, 1, 80, 4

; Spring flower (15pts): SOUND 1,1,100,4
.sound_hit3
    EQUW 1, 1, 100, 4

; Summer apple (20pts): SOUND 1,1,120,4
.sound_hit4
    EQUW 1, 1, 120, 4

; Acorn (incrementing): SOUND 1,1,30,6 (envelope 1: deep gulp)
.sound_hit5
    EQUW 1, 1, 30, 6

; Movement tick: SOUND 0,-2,4,1 (noise channel, quiet, periodic low buzz tick)
.sound_tick
    EQUW 0, -2, 4, 1

; ACORN letter collected: SOUND 1,2,200,4 (envelope 2 ding, high pitch)
.sound_letter
    EQUW 1, 2, 200, 4

; All 8 season acorns collected: SOUND 1,2,250,12 (envelope 2 ding, high pitch, long)
.sound_celebrate
    EQUW 1, 2, 250, 12

; Sound envelope 1: gulp effect
; Params: envelope, step_len, pitch1, pitch2, pitch3, steps1, steps2, steps3,
;         attack_change, decay_change, sustain_change, release_change,
;         attack_target, decay_target
.envelope_data
    EQUB 1         ; envelope number
    EQUB 1         ; step length (10ms per step)
    EQUB -6        ; pitch section 1: descend
    EQUB 0         ; pitch section 2: hold
    EQUB 0         ; pitch section 3: hold
    EQUB 8         ; steps in section 1
    EQUB 0         ; steps in section 2
    EQUB 0         ; steps in section 3
    EQUB 126       ; attack change (fast rise)
    EQUB -16       ; decay change
    EQUB 0         ; sustain change
    EQUB -16       ; release change
    EQUB 126       ; attack target
    EQUB 0         ; decay target

; Sound envelope 2: acorn "ding" (pitch rises then falls)
.envelope2_data
    EQUB 2         ; envelope number
    EQUB 1         ; step length (10ms per step)
    EQUB 8         ; pitch section 1: ascend
    EQUB -4        ; pitch section 2: slow descend
    EQUB 0         ; pitch section 3: hold
    EQUB 5         ; steps in section 1 (rise 40 over 50ms)
    EQUB 10        ; steps in section 2 (fall 40 over 100ms)
    EQUB 0         ; steps in section 3
    EQUB 126       ; attack change (fast rise)
    EQUB -4        ; decay change (slow fade)
    EQUB 0         ; sustain change
    EQUB -8        ; release change
    EQUB 126       ; attack target
    EQUB 0         ; decay target

; --- Season configuration table (8 bytes per season) ---
; Format: map_lo, map_hi, map_rows, scroll_div, item_char, item_colour, col_offset, item_skip
; All seasons share map_base. col_offset shifts columns, item_skip skips every Nth mushroom (0=none).
.season_config
    EQUB LO(map_base), HI(map_base), 64, 2, 246, 1, 5, 2      ; Autumn: ~17 mush (50%), offset 5
    EQUB LO(map_base), HI(map_base), 64, 2, 247, 7, 10, 3     ; Winter: ~22 mush (67%), offset 10
    EQUB LO(map_base), HI(map_base), 64, 2, 245, 5, 15, 4     ; Spring: ~25 mush (75%), offset 15
    EQUB LO(map_base), HI(map_base), 64, 2, 241, 4, 0, 0      ; Summer: 33 mush (100%), no offset

; ============================================================================
; Section: Map Data (single base map shared by all seasons)
; Pair format: row_number, type_col, ... &FF sentinel
; Item encoding (type_col byte):
;   &00-&13: mushroom at column 0-19
;   &20-&33: season item at column 0-19
;   &40-&53: acorn at column 0-19
; Empty rows need no data (parser skips rows with no matching pairs)
; All seasons use map_base with per-season col_offset and item_skip (mushrooms only)
; ============================================================================

; --- Base map (48 items, 97 bytes) - shared by all seasons ---
; 33 mushrooms, 14 apples, 1 acorn (at row 59, once per map cycle)
; Rows 57-58 and 60-61 kept empty to give clear space around the acorn
; MAX 1 ITEM PER ROW to avoid frame overrun from VDU calls
; Mushroom columns avoid {4,9,14,19} to prevent cap overflow after any offset
.map_base
    EQUB 0, &03, 1, &0F, 2, &08
    EQUB 4, &06, 5, &10
    EQUB 7, &0F, 8, &23
    EQUB 9, &0B, 10, &07, 11, &32
    EQUB 12, &21, 13, &0D, 14, &0A
    EQUB 18, &02, 19, &11, 20, &07
    EQUB 22, &0B, 23, &23
    EQUB 24, &28, 25, &10
    EQUB 27, &01, 28, &2C, 29, &07
    EQUB 30, &0F, 32, &03
    EQUB 33, &31, 34, &2A
    EQUB 35, &06, 36, &0D
    EQUB 38, &05, 39, &12
    EQUB 40, &22, 41, &0D
    EQUB 42, &08, 43, &10
    EQUB 44, &25, 45, &11
    EQUB 47, &06, 48, &0F, 49, &21
    EQUB 50, &0C, 52, &0A
    EQUB 53, &33, 55, &05, 56, &30
    EQUB 59, &4A
    EQUB 62, &22, 63, &10
    EQUB &FF

; --- Bonus map  ---
.map_bonus
    EQUB 0, &44, 2, &4D, 4, &48
    EQUB 6, &42, 8, &4F, 10, &46
    EQUB 12, &4B, 14, &43, 16, &50
    EQUB 18, &49, 20, &45, 22, &4E
    EQUB 24, &47, 26, &4C, 28, &41
    EQUB 30, &51
    EQUB 32, &4A, 34, &52, 36, &47, 38, &4E
    EQUB &FF

; --- Season name lookup tables ---
.season_name_lo
    EQUB LO(str_autumn), LO(str_winter), LO(str_spring), LO(str_summer), LO(str_bonus)
.season_name_hi
    EQUB HI(str_autumn), HI(str_winter), HI(str_spring), HI(str_summer), HI(str_bonus)
.acorn_target_col
    EQUB 4, 11, 13, 11, 6 ; target columns spelling ACORN (A=4,C=11,O=13,R=11,N=6)
.acorn_bit_table
    EQUB 1, 2, 4, 8, 16   ; bit masks for acorn_word (one per season)
.acorn_col_table
    EQUB 10, 3, 16, 7     ; rotating acorn columns (spread across playfield)

; --- In-game strings (null-terminated) ---
.str_autumn
    EQUS "Autumn Fall", 0
.str_winter
    EQUS "Winter Cold", 0
.str_spring
    EQUS "Spring Bloom", 0
.str_summer
    EQUS "Summer Rays", 0
.str_bonus
    EQUS "Bonus Bunch", 0

; ============================================================================
; Section: Sprite Preview Page (diagnostic — remove when no longer needed)
; Displays all game sprites on screen for visual inspection.
; Called once from game_init; safe to delete this block + the JSR call.
; ============================================================================
.show_sprite_page
    ; Print text labels
    LDA #4 : JSR OSWRCH          ; VDU 4 (text cursor mode)
    LDA #7 : JSR do_colour       ; white text
    ; Title
    LDA #3 : LDX #1 : JSR do_tab
    LDX #LO(str_ssp_title) : LDY #HI(str_ssp_title)
    JSR print_string
    ; Top row labels
    LDA #0 : LDX #3 : JSR do_tab
    LDX #LO(str_ssp_row1) : LDY #HI(str_ssp_row1)
    JSR print_string
    ; Bottom row labels
    LDA #0 : LDX #8 : JSR do_tab
    LDX #LO(str_ssp_row2) : LDY #HI(str_ssp_row2)
    JSR print_string
    ; Instruction
    LDA #3 : LDX #14 : JSR do_tab
    LDX #LO(str_ssp_key) : LDY #HI(str_ssp_key)
    JSR print_string

    ; Draw sprites from table (direct screen writes, independent of VDU mode)
    LDY #0
.ssp_loop
    LDA ssp_table,Y         ; text column (or &FF sentinel)
    CMP #&FF
    BEQ ssp_wait
    PHA                      ; save column
    INY
    LDA ssp_table,Y         ; text row
    TAX
    INY
    STY temp3                ; save table index
    PLA                      ; A = column
    JSR calc_item_addr       ; scr_addr = screen address for (col, row)
    LDY temp3
    LDA ssp_table,Y         ; sprite data lo
    STA copy_ptr_lo
    INY
    LDA ssp_table,Y         ; sprite data hi
    STA copy_ptr_hi
    INY
    STY temp3
    JSR draw_item            ; draw 4×8 sprite at scr_addr
    LDY temp3
    JMP ssp_loop
.ssp_wait
    JSR OSRDCH               ; wait for any key press
    LDA #12 : JSR OSWRCH     ; CLS - clear screen for game
    LDA #5 : JMP OSWRCH      ; VDU 5 (graphics mode) + tail-call return

; --- Sprite preview layout table: col, row, sprite_lo, sprite_hi ---
.ssp_table
    ; Top row (row 4-5): mushroom assembled, then seasonal apples + apple
    EQUB  1, 4, LO(spr_cap_left),  HI(spr_cap_left)
    EQUB  2, 4, LO(spr_cap_right), HI(spr_cap_right)
    EQUB  1, 5, LO(spr_stem),      HI(spr_stem)
    EQUB  5, 4, LO(spr_leaf),      HI(spr_leaf)
    EQUB  8, 4, LO(spr_snow),      HI(spr_snow)
    EQUB 11, 4, LO(spr_flower),    HI(spr_flower)
    EQUB 15, 4, LO(spr_apple),     HI(spr_apple)
    ; Bottom row (row 9-10): acorn stacked, caterpillar head
    EQUB  3, 9, LO(spr_acorn_top),    HI(spr_acorn_top)
    EQUB  3,10, LO(spr_acorn_bottom), HI(spr_acorn_bottom)
    EQUB  8, 9, LO(spr_caterpillar), HI(spr_caterpillar)
    EQUB &FF    ; sentinel

.str_ssp_title
    EQUS "SPRITE PREVIEW", 0
.str_ssp_row1
    EQUS " MU  LF TW FL  AP", 0
.str_ssp_row2
    EQUS "   AC   HD", 0
.str_ssp_key
    EQUS "PRESS ANY KEY", 0

.end

; ============================================================================
; Save to disc image
; ============================================================================
SAVE "GAME", start, end, start
PUTBASIC "caterpillar.bas", "CATER"
PUTTEXT "!BOOT", "!BOOT", &FFFF
