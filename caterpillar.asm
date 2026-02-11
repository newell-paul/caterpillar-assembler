; ============================================================================
; Caterpillar - BBC Micro 6502 Assembly (MODE 7 BASIC wrapper version) v0.0.6
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
sprite_ptr_lo = &62    ; sprite data pointer (low byte)
sprite_ptr_hi = &63    ; sprite data pointer (high byte)
cat_px_x    = &64      ; caterpillar pixel X (0-159)
cat_px_y    = &65      ; caterpillar pixel Y (0-255)
anim_frame  = &66      ; animation frame counter
move_timer  = &67      ; movement speed divider (counts frames between moves)
sprite_drawn = &68     ; 1 if sprite is currently on screen (save buffer valid)
prev_scr_lo  = &69     ; previous sprite screen address lo
prev_scr_hi  = &6A     ; previous sprite screen address hi
prev_scanline = &6B    ; previous sprite starting scanline (py AND 7)
scroll_py     = &6C    ; hardware scroll offset in pixels (0-255, wraps)
prev_px_x     = &6D    ; previous pixel X (for body sprite alignment)
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
fruit_char  = &7E      ; current fruit character code
fruit_col   = &7F      ; current fruit colour
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
acorn_pending = &6F    ; column for pending acorn draw (0=none, unused)
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
    LDA #19 : JSR OSBYTE

    ; MODE 2 + disable cursor + VDU 5 (table-driven)
    LDX #LO(vdu_init_data)
    LDY #HI(vdu_init_data)
    LDA #13
    JSR send_vdu_seq

    ; Define characters 240-250
    JSR define_characters

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
    LDA #0 : STA acorn_score
    STA collision_key_prev
    LDA #1 : STA collision_on
    LDA #2 : STA scroll_div : STA scroll_count  ; initial scroll speed
    JSR enter_transition ; show "Autumn", load empty transition map

; ============================================================================
; Section: Main Game Loop
; Variable-rate scroll driven by season config. Fast path does vsync + sprite.
; Slow path (every 4th frame) handles collision, sound, and input.
; ============================================================================
.game_loop
    ; Wait for 1 vsync (50Hz for smooth pixel movement)
    LDA #19 : JSR OSBYTE

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
    LDA #0 : STA item_counter  ; reset skip counter for new cycle
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
    BNE ck_debounce         ; already held, don't toggle again
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
.ck_debounce
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
    LDA cat_px_x : STA prev_px_x
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

    ; Set up copy_ptr to point to body_save_N (wridx * 40)
    ; Lookup from table for speed
    LDA body_buf_addr_lo,X
    STA copy_ptr_lo
    LDA body_buf_addr_hi,X
    STA copy_ptr_hi

    ; Copy 40 bytes from save_buffer to (copy_ptr)
    LDY #39
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

    ; Restore 40 bytes (5 cols x 8 rows) to screen from body buffer
    ; Uses copy_ptr as sequential read pointer (advanced by 5 each row)
    ; Y is swapped between buffer offset (0-4) and screen offset (0,8,16,24,32)
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
    ; Byte 4: buffer[4] -> screen+32
    LDY #4
    LDA (copy_ptr_lo),Y
    LDY #32
    STA (scr_addr_lo),Y
    ; Advance copy_ptr by 5
    CLC
    LDA copy_ptr_lo
    ADC #5
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
    LDA season_config+4,X
    STA fruit_char
    LDA season_config+5,X
    STA fruit_col
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
    ; TAB(season_tab_col, 1) - centred for variable-length names
    LDX temp0
    LDA season_tab_col,X
    LDX #1 : JSR do_tab
    ; Print season name string
    LDX temp0
    LDA season_name_lo,X
    STA temp1
    LDA season_name_hi,X
    TAY
    LDX temp1
    JSR print_string
    RTS

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
;   &20-&33: fruit at column N-32
;   &40-&53: acorn at column N-64
;   &FF: end of row
.draw_map_row
    ; VDU 4 - text cursor mode (needed for row clear VDU 28/12)
    LDA #4
    JSR OSWRCH

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

    ; Fruits (&20+) bypass the skip check - always drawn
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

.dmr_no_offset
    ; Acorns arrive here with original type_col in temp2 (no offset applied)
    LDA temp2
    ; Determine item type
    CMP #&40
    BCS dmr_acorn       ; >= &40: acorn
    CMP #&20
    BCS dmr_fruit       ; >= &20: fruit
    ; Fall through: mushroom (&00-&13)

    ; --- Mushroom ---
    STA temp0           ; column
    ; COLOUR 2 (green)
    LDA #2
    JSR do_colour
    ; TAB(col,1) CHR$242 CHR$243
    LDA temp0
    LDX #1
    JSR do_tab
    LDA #242
    JSR OSWRCH
    LDA #243
    JSR OSWRCH
    ; COLOUR 3 (yellow)
    LDA #3
    JSR do_colour
    ; TAB(col,2) CHR$244
    LDA temp0
    LDX #2
    JSR do_tab
    LDA #244
    JSR OSWRCH
    JMP dmr_next_item

.dmr_fruit
    ; Fruit: column = item - &20
    SEC
    SBC #&20
    STA temp0           ; column
    ; COLOUR fruit_col
    LDA fruit_col
    JSR do_colour
    ; TAB(col,1) CHR$ fruit_char
    LDA temp0
    LDX #1
    JSR do_tab
    LDA fruit_char
    JSR OSWRCH
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
    ; COLOUR 11 (bright yellow)
    LDA #11
    JSR do_colour
    ; TAB(col,1) CHR$248
    LDA temp0
    LDX #1
    JSR do_tab
    LDA #248
    JSR OSWRCH
    ; COLOUR 10 (bright green)
    LDA #10
    JSR do_colour
    ; TAB(col,2) CHR$249
    LDA temp0
    LDX #2
    JSR do_tab
    LDA #249
    JSR OSWRCH

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

    ; VDU 5 - graphics cursor mode
    LDA #5
    JMP OSWRCH

; ============================================================================
; Section: PROCcheckhit - direct screen memory collision detection
; Scans ALL 40 save_buffer bytes (5 byte-cols x 8 rows) for any non-black
; left pixel. Detects items at any position under the sprite — left edge,
; centre, or right edge — so collision works when approaching from any side.
; Called from proc_caterpillar after save_background, before draw_sprite.
; ============================================================================
.proc_checkhit
    ; Skip collision check if toggled off
    LDA collision_on
    BNE pch_active
    RTS
.pch_active
    ; Scan all 40 save_buffer bytes for any non-black left pixel
    LDX #39
    LDA #0
.pch_scan
    ORA save_buffer,X
    DEX
    BPL pch_scan
    ; A = OR of all 40 bytes; if zero, nothing under sprite
    AND #&AA            ; isolate left pixel bits
    BNE pch_has_colour
    RTS                 ; all black = no collision
.pch_has_colour
    ; Reverse lookup: find logical colour from left pixel bits
    LDX #15
.pch_find
    CMP colour_left,X
    BEQ pch_found
    DEX
    BPL pch_find
    RTS                 ; no match (mixed colours from OR, rare)
.pch_found
    ; X = logical colour (0-15)
    ; Check for colour 2 (mushroom cap) or 3 (mushroom stem) = crash
    CPX #2
    BEQ is_crash
    CPX #3
    BNE not_crash
.is_crash
    JMP proc_crash
.not_crash
    ; Eat the item: zero save_buffer, clear from screen via VDU, then score
    TXA : PHA           ; save colour on stack
    ; Zero save_buffer so future background restore writes black
    LDA #0 : LDX #39
.clear_sb
    STA save_buffer,X
    DEX
    BPL clear_sb
    ; Clear item from screen using VDU (MOS handles CRTC scroll)
    ; Print 2 spaces covering sprite's full width (16px = 2 text cols)
    LDA #4 : JSR OSWRCH          ; VDU 4 - text cursor mode
    LDA #0 : JSR do_colour       ; text colour 0 (black)
    LDA cat_px_x
    LSR A : LSR A : LSR A        ; A = text column of sprite left edge
    LDX #24                      ; text row (caterpillar visual row)
    JSR do_tab                   ; VDU 31, col, 25
    LDA #32 : JSR OSWRCH         ; space 1 (left half)
    LDA #32 : JSR OSWRCH         ; space 2 (right half)
    LDA #5 : JSR OSWRCH          ; VDU 5 - back to graphics cursor
    ; Restore colour and score
    PLA : TAX
    CPX #1
    BNE not_col1
    LDX #LO(sound_hit1) : LDY #HI(sound_hit1) : LDA #5
    JMP add_score_and_sound
.not_col1
    CPX #7
    BNE not_col7
    LDX #LO(sound_hit2) : LDY #HI(sound_hit2) : LDA #10
    JMP add_score_and_sound
.not_col7
    CPX #5
    BNE not_col5
    LDX #LO(sound_hit3) : LDY #HI(sound_hit3) : LDA #15
    JMP add_score_and_sound
.not_col5
    CPX #4
    BNE not_col4
    LDX #LO(sound_hit4) : LDY #HI(sound_hit4) : LDA #20
    JMP add_score_and_sound
.not_col4
    CPX #11
    BNE no_hit
    LDA acorn_score : CLC : ADC #10 : STA acorn_score
    LDX #LO(sound_hit5) : LDY #HI(sound_hit5)
    JMP add_score_and_sound
.no_hit
    RTS

; Common score addition + sound routine
; Entry: X/Y = sound block address, A = points to add
.add_score_and_sound
    PHA                 ; save points
    ; Hit-stop: freeze 2 frames for kinetic "gulp" feel
    STX temp0 : STY temp1
    LDA #19 : JSR OSBYTE
    LDA #19 : JSR OSBYTE
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
    LDA #19
    JSR OSBYTE
    LDA osword_blk+2
    CLC : ADC #1
    CMP #0               ; stop when &FF wraps to 0
    BNE crash_loop

    ; *FX15,0 - flush all buffers
    LDA #15
    LDX #0
    JSR OSBYTE

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


; ============================================================================
; Section: Character Definitions
; ============================================================================
.define_characters
    ; Define characters 240-249 using VDU 23 sequences
    ; Each character: VDU 23, char_num, b0, b1, b2, b3, b4, b5, b6, b7
    LDX #0              ; index into char_data
    LDA #240            ; starting character number
    STA temp0
.defchar_loop
    LDA #23
    JSR OSWRCH
    LDA temp0           ; character number
    JSR OSWRCH
    ; Send 8 bytes of bitmap data
    LDY #0
.defchar_byte
    LDA char_data,X
    JSR OSWRCH
    INX
    INY
    CPY #8
    BNE defchar_byte
    ; Next character
    INC temp0
    LDA temp0
    CMP #250            ; done after char 249
    BNE defchar_loop
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
; Save 5 byte-columns (40 bytes) of screen data into save_buffer
; Always saves 5 cols to support both even (4-col) and odd (5-col) sprites
; Entry: scr_addr_lo/hi = top-left screen address
;        temp0 = starting scanline (py AND 7)
; Clobbers: A, X, Y, temp0, temp1
.save_background
    LDX #0              ; buffer index
    LDA #8              ; row counter
    STA temp1
.sb_row_loop
    ; Read 5 bytes at offsets 0, 8, 16, 24, 32
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
    LDY #32
    LDA (scr_addr_lo),Y
    STA save_buffer,X
    INX
    JSR advance_scanline
    DEC temp1
    BNE sb_row_loop
    RTS

; --- restore_background ---
; Restore 5 byte-columns (40 bytes) from save_buffer to screen
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
    LDY #32
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
    LDA sprite_data_even,X
    STA (scr_addr_lo),Y
    INX
    LDY #8
    LDA sprite_data_even,X
    STA (scr_addr_lo),Y
    INX
    LDY #16
    LDA sprite_data_even,X
    STA (scr_addr_lo),Y
    INX
    LDY #24
    LDA sprite_data_even,X
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

; --- Sprite save buffer (40 bytes for 5 byte-columns x 8 rows) ---
.save_buffer
    SKIP 40

; --- Body ring buffer data ---
; Screen address and scanline for each body segment (5 slots)
.body_scr_lo
    SKIP BODY_MAX
.body_scr_hi
    SKIP BODY_MAX
.body_scanln
    SKIP BODY_MAX

; Save buffers for body segments (40 bytes each, 5 slots = 200 bytes)
.body_save_0
    SKIP 40
.body_save_1
    SKIP 40
.body_save_2
    SKIP 40
.body_save_3
    SKIP 40
.body_save_4
    SKIP 40

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

; --- Pre-encoded caterpillar sprite for MODE 2, colour 6 (cyan) ---
; Even-aligned: 8 rows x 4 bytes = 32 bytes (sprite starts at left pixel of byte)
; Derived from char 240 bitmap: 153, 90, 24, 219, 90, 219, 90, 219
; Colour 6 left pixel = &28, right pixel = &14, both = &3C, neither = &00
.sprite_data_even
    ; Row 0: 10011001 → (L,_),(_,R),(L,_),(_,R)
    EQUB &28, &14, &28, &14
    ; Row 1: 01011010 → (_,R),(_,R),(L,_),(L,_)
    EQUB &14, &14, &28, &28
    ; Row 2: 00011000 → (_,_),(_,R),(L,_),(_,_)
    EQUB &00, &14, &28, &00
    ; Row 3: 11011011 → (L,R),(_,R),(L,_),(L,R)
    EQUB &3C, &14, &28, &3C
    ; Row 4: 01011010
    EQUB &14, &14, &28, &28
    ; Row 5: 11011011
    EQUB &3C, &14, &28, &3C
    ; Row 6: 01011010
    EQUB &14, &14, &28, &28
    ; Row 7: 11011011
    EQUB &3C, &14, &28, &3C

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

; --- MODE 2 colour encoding tables ---
; In MODE 2, each byte encodes 2 pixels (left and right).
; Each pixel has 4 bits of colour (16 colours).
; Bit layout: L3 R3 L2 R2 L1 R1 L0 R0
; (L = left pixel bits, R = right pixel bits)
;
; Left pixel colour table: colour value -> byte with just left pixel set
; Right pixel colour table: colour value -> byte with just right pixel set
; To make a byte with both pixels: left_table[left_col] OR right_table[right_col]

.colour_left   ; colour in left pixel position (bits 7,5,3,1)
    EQUB &00   ; colour 0  = 0000 -> 0.0.0.0. = &00
    EQUB &02   ; colour 1  = 0001 -> 0.0.0.1. = &02
    EQUB &08   ; colour 2  = 0010 -> 0.0.1.0. = &08
    EQUB &0A   ; colour 3  = 0011 -> 0.0.1.1. = &0A
    EQUB &20   ; colour 4  = 0100 -> 0.1.0.0. = &20
    EQUB &22   ; colour 5  = 0101 -> 0.1.0.1. = &22
    EQUB &28   ; colour 6  = 0110 -> 0.1.1.0. = &28
    EQUB &2A   ; colour 7  = 0111 -> 0.1.1.1. = &2A
    EQUB &80   ; colour 8  = 1000 -> 1.0.0.0. = &80
    EQUB &82   ; colour 9  = 1001 -> 1.0.0.1. = &82
    EQUB &88   ; colour 10 = 1010 -> 1.0.1.0. = &88
    EQUB &8A   ; colour 11 = 1011 -> 1.0.1.1. = &8A
    EQUB &A0   ; colour 12 = 1100 -> 1.1.0.0. = &A0
    EQUB &A2   ; colour 13 = 1101 -> 1.1.0.1. = &A2
    EQUB &A8   ; colour 14 = 1110 -> 1.1.1.0. = &A8
    EQUB &AA   ; colour 15 = 1111 -> 1.1.1.1. = &AA

; --- Character bitmap data (chars 240-250) ---
; 11 characters x 8 bytes = 88 bytes
.char_data
    ; CHR$240 - caterpillar body
    EQUB 153, 90, 24, 219, 90, 219, 90, 219
    ; CHR$241 - fruit
    EQUB 6, 24, 126, 223, 191, 191, 223, 126
    ; CHR$242 - mushroom cap left
    EQUB 0, 0, 0, 15, 63, 127, 255, 255
    ; CHR$243 - mushroom cap right
    EQUB 0, 0, 0, 0, 224, 240, 248, 248
    ; CHR$244 - mushroom stem
    EQUB 7, 7, 7, 7, 7, 0, 0, 0
    ; CHR$245 - leaf/food
    EQUB 8, 28, 28, 107, 127, 107, 8, 28
    ; CHR$246 - leaf
    EQUB 128, 112, 248, 252, 254, 126, 31, 7
    ; CHR$247 - twig
    EQUB 133, 201, 113, 49, 119, 30, 4, 4
    ; CHR$248 - acorn top
    EQUB 0, 24, 44, 94, 94, 191, 191, 255
    ; CHR$249 - acorn bottom
    EQUB 0, 255, 126, 60, 7, 0, 0, 0

; --- Sound data blocks (8 bytes each) ---
; Format: channel(2), amplitude(2), pitch(2), duration(2)

; Eat sounds use envelope 1 (gulp: descending pitch, quick decay)
; Hit colour 1 (leaves, 5pts): SOUND 1,1,60,4
.sound_hit1
    EQUW 1, 1, 60, 4

; Hit colour 7 (twigs, 10pts): SOUND 1,1,80,4
.sound_hit2
    EQUW 1, 1, 80, 4

; Hit colour 5 (flowers, 15pts): SOUND 1,1,100,4
.sound_hit3
    EQUW 1, 1, 100, 4

; Hit colour 4 (fruits, 20pts): SOUND 1,1,120,4
.sound_hit4
    EQUW 1, 1, 120, 4

; Hit colour 11 (acorns, 50pts): SOUND 1,1,30,6 (envelope 1: deep gulp)
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
; Format: map_lo, map_hi, map_rows, scroll_div, fruit_char, fruit_colour, col_offset, item_skip
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
;   &20-&33: season fruit at column 0-19
;   &40-&53: acorn at column 0-19
; Empty rows need no data (parser skips rows with no matching pairs)
; All seasons use map_base with per-season col_offset and item_skip (mushrooms only)
; ============================================================================

; --- Base map (48 items, 97 bytes) - shared by all seasons ---
; 33 mushrooms, 14 fruits, 1 acorn (at row 59, once per map cycle)
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
.season_tab_col
    EQUB 4, 4, 4, 4, 4   ; TAB start column for centred name display
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

.end

; ============================================================================
; Save to disc image
; ============================================================================
SAVE "GAME", start, end, start
PUTBASIC "caterpillar.bas", "CATER"
PUTTEXT "!BOOT", "!BOOT", &FFFF
