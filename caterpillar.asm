; ======================================================================================
; Caterpillar - BBC Micro 6502 Assembly (MODE 7 BASIC wrapper version) v0.9.4
; Converted from BBC BASIC by Paul Newell with some assistance from Claude Code (c) 2026
; Game engine only - title/menu/scores handled by BASIC in MODE 7
; ======================================================================================

OSWRCH  = &FFEE
OSRDCH  = &FFE0
OSBYTE  = &FFF4
OSWORD  = &FFF1

scr_addr_lo = &60
scr_addr_hi = &61

cat_px_x    = &64
cat_px_y    = &65
anim_frame  = &66
move_timer  = &67
sprite_drawn = &68
prev_scr_lo  = &69
prev_scr_hi  = &6A
prev_scanline = &6B
scroll_py     = &6C
item_buf_wr    = &6D
prev_scroll_py = &6E
acorn_word  = &9C

map_ptr_lo   = &70
map_ptr_hi   = &71
map_row_idx  = &72
season       = &73

score_lo    = &74
score_hi    = &75
hiscore_lo  = &76
hiscore_hi  = &77
acorn_score = &78
map_cycle   = &79
temp0       = &7A
temp1       = &7B
temp2       = &7C
temp3       = &7D
pch_item_col  = &62
pch_item_type = &63

osword_blk  = &80
scroll_div   = &90
scroll_count = &91
season_rows  = &92
map_base_lo  = &93
map_base_hi  = &94

body_count   = &96
body_wridx   = &97
body_rdidx   = &98
copy_ptr_lo  = &99
copy_ptr_hi  = &9A
acorn_col_idx = &9B
item_buf_rd    = &6F
bonus_phase   = &9D
transition_phase = &9E
game_result   = &9F

PX_LEFT_BOUND  = 25
PX_RIGHT_BOUND = 134
PX_CAT_INIT_X  = 76
PX_CAT_INIT_Y  = 192
MOVE_ACCUM     = 164

CAT_W          = 8
MUSH_R_OFF     = 11
ITEM_R_OFF     = 7

; Bonus-round giant-letter geometry: 5 acorn columns, centred, 3-cell pitch (cols 4,7,10,13,16)
ACORN_BOX_LEFT = 4              ; playfield col of the leftmost acorn column
ACORN_BOX_PITCH = 3            ; cells between adjacent acorn columns (gives the horizontal gap)
ACORN_ROW_PITCH = 4           ; draw_map_row steps between successive letter-rows (vertical gap)
ACORN_LETTER_GAP = 26         ; blank rows between one finished letter and the next (tunable)

BODY_MAX       = 5

MACRO RINGINC idx, n
    LDX idx
    INX
    CPX #n
    BCC skip
    LDX #0
.skip
    STX idx
ENDMACRO

MACRO DRAWCELL row, sprite
    LDX #row
    JSR calc_item_addr
    LDA #LO(sprite) : STA copy_ptr_lo
    LDA #HI(sprite) : STA copy_ptr_hi
    JSR draw_item
ENDMACRO

ORG &1900
GUARD &3000

.start
    TSX
    STX saved_sp
    JMP game_init

; &1907 = saved_sp, &1908 = saved_acorn_word
.saved_sp
    EQUB 0
.saved_acorn_word
    EQUB 0
.saved_score_lo
    EQUB 0
.saved_score_hi
    EQUB 0
.saved_hiscore_lo
    EQUB 0
.saved_hiscore_hi
    EQUB 0

.return_to_basic
    LDA acorn_word
    STA saved_acorn_word        ; copy to non-ZP storage before BASIC can corrupt it
    LDA saved_score_lo   : STA score_lo
    LDA saved_score_hi   : STA score_hi
    LDA saved_hiscore_lo : STA hiscore_lo
    LDA saved_hiscore_hi : STA hiscore_hi
    LDX saved_sp
    TXS                         ; restore stack pointer (clean regardless of call depth)
    RTS                         ; returns to BASIC's CALL

.game_init
    LDA #200
    LDX #3
    JSR OSBYTE

    LDA #0
    TAY
    LDX #&30
    STY &80 : STX &81           ; pointer = &3000
.clear_scr
    STA (&80),Y
    INY
    BNE clear_scr
    INC &81
    LDX &81
    CPX #&7C
    BNE clear_scr

    JSR vsync_wait

    LDX #LO(vdu_init_data)
    LDY #HI(vdu_init_data)
    LDA #13
    JSR send_vdu_seq

    LDA #8
    LDX #LO(envelope_data)
    LDY #HI(envelope_data)
    JSR OSWORD

    LDA #8
    LDX #LO(envelope2_data)
    LDY #HI(envelope2_data)
    JSR OSWORD

    LDA #PX_CAT_INIT_X
    STA cat_px_x
    LDA #PX_CAT_INIT_Y
    STA cat_px_y

    LDA #0
    LDX #(&75 - &66)
.zi_loop1
    STA &66,X
    DEX
    BPL zi_loop1
    LDX #(&9E - &95)
.zi_loop2
    STA &95,X
    DEX
    BPL zi_loop2
    STA acorn_score
    STA collision_key_prev
    LDA #1 : STA collision_on
    LDA #2 : STA scroll_div : STA scroll_count ; initial scroll speed
    LDA #&FF : LDX #23
.init_item_ring
    STA item_col,X
    DEX
    BPL init_item_ring
    LDA #0 : STA item_buf_wr
    LDA #1 : STA item_buf_rd
    JSR enter_transition        ; show "Autumn", load empty transition map

.game_loop
    JSR vsync_wait

    INC anim_frame

    JSR proc_caterpillar

    DEC scroll_count
    BNE after_scroll
    LDA scroll_div
    STA scroll_count
    JSR draw_map_row
    INC map_row_idx
    LDA map_row_idx
    CMP season_rows
    BCC after_scroll
    LDA transition_phase
    BNE transition_done         ; transition complete -> load real map
    LDA bonus_phase
    BNE bonus_complete          ; bonus map done -> show completed
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
    JSR load_season             ; load the real season map
    JMP after_scroll
.load_bonus_map
    JSR setup_bonus_letters     ; build lit_list from acorn_word; A = lit_count
    BNE lbm_have_letters
    JMP show_completed          ; no ACORN letters lit -> skip the bonus entirely
.lbm_have_letters
    LDA #0
    STA map_row_idx
    STA bonus_letter : STA bonus_step : STA bonus_gap
    LDX #23
.lbm_clear_mask
    STA acorn_mask,X            ; clear stale ring bits left over from the transition rows
    DEX
    BPL lbm_clear_mask
    LDA #6 : STA bonus_subrow    ; rows emitted 6->0 so the letter scrolls in upright
    LDA #250 : STA season_rows  ; high cap; real completion is driven by exhausting lit_list
    JMP after_scroll
.bonus_complete
    JMP show_completed
.after_scroll

    LDA anim_frame
    AND #3
    BNE skip_slow_path

    LDX #(256-83)
    JSR read_key
    BNE ck_not_pressed
    LDA collision_key_prev
    BNE ck_done                 ; already held, don't toggle again
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
    LDA #7
    LDX #LO(sound_tick)
    LDY #HI(sound_tick)
    JSR OSWORD

.skip_slow_path
    JMP game_loop

.round_over
    LDA acorn_score
    CMP #240
    BCS ro_bonus_hi
    CMP #200
    BCS ro_bonus_mid
    CMP #160
    BCS ro_bonus_lo
    JMP ro_no_acorn_bonus
.ro_bonus_hi
    LDA #LO(2000) : STA temp0 : LDA #HI(2000) : STA temp1
    JMP ro_add_bonus
.ro_bonus_mid
    LDA #LO(1000) : STA temp0 : LDA #HI(1000) : STA temp1
    JMP ro_add_bonus
.ro_bonus_lo
    LDA #LO(500) : STA temp0 : LDA #HI(500) : STA temp1
.ro_add_bonus
    CLC
    LDA score_lo : ADC temp0 : STA score_lo
    LDA score_hi : ADC temp1 : STA score_hi
    LDA #7
    LDX #LO(sound_celebrate)
    LDY #HI(sound_celebrate)
    JSR OSWORD
.ro_no_acorn_bonus
    LDA #1
    STA bonus_phase
    JSR enter_transition        ; show "Bonus", load empty map
    JMP game_loop

.proc_caterpillar
    CLC
    LDA move_timer
    ADC #MOVE_ACCUM
    STA move_timer
    LDA #0
    ADC #0
    STA temp3                   ; temp3 = 1 if movement frame, 0 if not

    LDA sprite_drawn
    BEQ pc_draw_head

    LDA scroll_py
    CMP prev_scroll_py
    BNE pc_scroll

    LDA temp3
    BEQ pc_idle                 ; no scroll + no movement: nothing to do
    LDA prev_scr_lo : STA scr_addr_lo
    LDA prev_scr_hi : STA scr_addr_hi
    LDA prev_scanline : STA temp0
    JSR restore_background
    JMP pc_check_keys

.pc_idle
    RTS

.pc_scroll
    LDA body_count
    CMP #BODY_MAX
    BCC pc_no_evict
    JSR erase_oldest_body
.pc_no_evict
    JSR add_body_segment
    LDA temp3
    BNE pc_check_keys
    JMP pc_draw_head

.pc_check_keys
    LDX #(256-98)
    JSR read_key
    BNE pc_no_left
    LDA cat_px_x
    CMP #PX_LEFT_BOUND+2        ; must be > left bound + 1
    BCC pc_no_left
    DEC cat_px_x                ; move 2 pixels left
    DEC cat_px_x
.pc_no_left

    LDX #(256-102)
    JSR read_key
    BNE pc_no_right
    LDA cat_px_x
    CMP #PX_RIGHT_BOUND-1       ; must be < right bound - 1
    BCS pc_no_right
    INC cat_px_x                ; move 2 pixels right
    INC cat_px_x
.pc_no_right

.pc_draw_head
    JSR prep_sprite_addr

    LDA scr_addr_lo : STA prev_scr_lo
    LDA scr_addr_hi : STA prev_scr_hi
    LDA temp0 : STA prev_scanline
    LDA scroll_py : STA prev_scroll_py

    JSR save_background
    JSR proc_checkhit           ; check BEFORE drawing (reads save_buffer)
    JSR prep_sprite_addr        ; recalc (save modifies scr_addr)
    JSR draw_sprite
    LDA #1
    STA sprite_drawn
    RTS

.add_body_segment
    LDX body_wridx
    LDA prev_scr_lo
    STA body_scr_lo,X
    LDA prev_scr_hi
    STA body_scr_hi,X
    LDA prev_scanline
    STA body_scanln,X

    LDA body_buf_addr_lo,X
    STA copy_ptr_lo
    LDA body_buf_addr_hi,X
    STA copy_ptr_hi

    LDY #31
.abs_copy_loop
    LDA save_buffer,Y
    STA (copy_ptr_lo),Y
    DEY
    BPL abs_copy_loop

    RINGINC body_wridx, BODY_MAX

    INC body_count
    RTS

.erase_oldest_body
    LDX body_rdidx

    LDA body_scr_lo,X
    STA scr_addr_lo
    LDA body_scr_hi,X
    STA scr_addr_hi
    LDA body_scanln,X
    STA temp0

    LDA body_buf_addr_lo,X
    STA copy_ptr_lo
    LDA body_buf_addr_hi,X
    STA copy_ptr_hi

    LDA #8
    STA temp1                   ; row counter
.eob_row_loop
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

    RINGINC body_rdidx, BODY_MAX

    DEC body_count
    RTS

.load_season
    LDA season
    ASL A                       ; A = season * 2
    STA temp0
    ASL A                       ; A = season * 4
    CLC
    ADC temp0                   ; A = season * 6
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
    STA scroll_count            ; prime the countdown
    LDA season_config+4,X
    STA col_offset
    LDA season_config+5,X
    STA item_skip
    LDA #0
    STA map_row_idx
    STA item_counter            ; reset skip counter
    STA map_cycle               ; reset cycle counter for new season
    RTS

.enter_transition
    LDA #1 : STA transition_phase
    LDA #0 : STA map_row_idx
    LDA #76 : STA season_rows   ; empty scrolling for transition
    RTS

; Build lit_list: the ordered indices (0=A..4=N) of letters whose acorn_word bit is set.
; Returns lit_count in A (and Z flag set when zero, for the caller's skip test).
.setup_bonus_letters
    LDX #0                      ; X = letter index 0..4
    LDY #0                      ; Y = write position in lit_list
.sbl_loop
    LDA acorn_word
    AND acorn_bit_table,X       ; is letter X lit?
    BEQ sbl_skip
    TXA
    STA lit_list,Y              ; record this letter's index
    INY
.sbl_skip
    INX
    CPX #5
    BNE sbl_loop
    STY lit_count
    TYA                         ; A = count, sets Z if zero
    RTS

.draw_season_name
    LDX season
    LDA bonus_phase
    BEQ dsn_got_idx
    LDX #4
.dsn_got_idx
    STX temp0
    LDA #6
    JSR do_colour
    LDA #4
    LDX #1 : JSR do_tab
    LDX temp0
    LDA season_name_lo,X
    STA temp1
    LDA season_name_hi,X
    TAY
    LDX temp1
    JMP print_string            ; tail call

.check_acorn_letter
    LDX season
    LDA bonus_phase
    BEQ cal_season
    LDX #4
.cal_season
    LDA acorn_word
    AND acorn_bit_table,X
    BNE cal_done
    LDA cat_px_x
    LSR A : LSR A : LSR A
    CMP acorn_target_col,X
    BNE cal_done                ; must be exactly on the target column
    LDA acorn_word
    ORA acorn_bit_table,X
    STA acorn_word
    LDA acorn_target_col,X
    STA temp1                   ; save target column
    LDA map_row_idx
    SEC
    SBC #31
    TAX                         ; X = screen row
    LDA temp1                   ; A = column
    JSR do_tab
    LDA #32                     ; space character
    JSR OSWRCH
    LDA #7
    LDX #LO(sound_letter)
    LDY #HI(sound_letter)
    JSR OSWORD
.cal_done
    RTS

;   &00-&13: mushroom at column N (2 chars wide)
;   &20-&33: item at column N-32
;   &40-&53: acorn at column N-64
;   &FF: end of row
.draw_map_row
    LDA #4
    JSR OSWRCH

    LDX item_buf_wr
    LDA #&FF
    STA item_col,X

    LDA transition_phase
    BEQ dmr_not_transition
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
.dmr_not_transition
    LDA bonus_phase
    BEQ dmr_has_items
    JMP dmr_draw_bonus_letter   ; bonus round (post-transition): draw the next giant-letter row
.dmr_has_items

    LDY #0
.dmr_loop
    LDA (map_ptr_lo),Y          ; peek at row number
    CMP map_row_idx
    BEQ dmr_row_match           ; row matches, parse items
    JMP dmr_done_items          ; not this row (or &FF sentinel)
.dmr_row_match
    INY
    LDA (map_ptr_lo),Y          ; type_col byte
    INY
    STY temp3

    STA temp2                   ; save type_col before skip check clobbers A

    CMP #&40
    BCS dmr_no_offset

    CMP #&20
    BCS dmr_apply_offset

    LDA item_skip
    BEQ dmr_apply_offset        ; 0 = no skipping, draw all
    INC item_counter
    LDA item_counter
    CMP item_skip
    BCC dmr_apply_offset        ; counter < skip -> draw this item
    LDA #0
    STA item_counter            ; reset counter, skip this item
    JMP dmr_next_item

.dmr_apply_offset
    LDA temp2                   ; restore type_col
    AND #&1F                    ; extract column (0-19)
    CLC
    ADC col_offset
    CMP #20
    BCC dmr_no_col_wrap
    SBC #20                     ; carry is set from CMP, so SBC #20 is correct
.dmr_no_col_wrap
    STA temp0                   ; adjusted column
    LDA temp2
    AND #&60                    ; type bits only
    ORA temp0                   ; reconstruct type_col with new column
    STA temp2                   ; write back so offset is used by drawing code

.dmr_no_offset
    LDA temp2
    CMP #&40
    BCC dmr_not_acorn           ; < &40: not acorn
    JMP dmr_acorn
.dmr_not_acorn
    CMP #&20
    BCS dmr_item                ; >= &20: apple

    STA temp0                   ; column
    LDA temp0
    DRAWCELL 1, spr_cap_left
    LDA temp0
    CLC : ADC #1
    DRAWCELL 1, spr_cap_right
    LDA temp0
    DRAWCELL 2, spr_stem
    LDX item_buf_wr
    LDA temp0 : STA item_col,X
    LDA #0 : STA item_type,X    ; type 0 = mushroom
    JMP dmr_next_item

.dmr_item
    SEC
    SBC #&20
    STA temp0                   ; column
    LDX item_buf_wr
    STA item_col,X              ; A still has column
    LDA #1 : STA item_type,X    ; type 1 = item
    LDA temp0
    LDX #1
    JSR calc_item_addr
    LDX season
    LDA item_spr_lo,X : STA copy_ptr_lo
    LDA item_spr_hi,X : STA copy_ptr_hi
    JSR draw_item
    JMP dmr_next_item

.dmr_acorn
    LDX acorn_col_idx
    LDA acorn_col_table,X
    STA temp0
    INX
    CPX #4
    BCC dmr_acorn_no_wrap
    LDX #0
.dmr_acorn_no_wrap
    STX acorn_col_idx
    LDX item_buf_wr
    LDA temp0 : STA item_col,X
    LDA #2 : STA item_type,X    ; type 2 = acorn
    LDA temp0
    DRAWCELL 1, spr_acorn_top
    LDA temp0
    DRAWCELL 2, spr_acorn_bottom

.dmr_next_item
    LDY temp3                   ; restore map index
    JMP dmr_loop

.dmr_done_items
    TYA
    CLC
    ADC map_ptr_lo
    STA map_ptr_lo
    LDA map_ptr_hi
    ADC #0
    STA map_ptr_hi
    JMP dmr_no_name             ; normal path done -> scroll tail (do NOT fall into bonus draw)

; Bonus round: emit one screen row of the giant falling letter, then fall through to the
; shared scroll tail. State machine over bonus_gap / bonus_step / bonus_subrow:
;   gap>0      -> blank separator row; when it expires, advance to the next lit letter
;   step>0     -> blank vertical-pitch row inside the current letter
;   step==0    -> draw letter-row bonus_subrow, then schedule the pitch/gap
.dmr_draw_bonus_letter
    LDX item_buf_wr
    LDA #0
    STA acorn_mask,X            ; default: no acorns on this row (blank)

    LDA bonus_gap
    BEQ ddbl_not_gap
    DEC bonus_gap               ; counting down the gap between letters
    BEQ ddbl_gap_expired
    JMP ddbl_blank
.ddbl_blank_near
    JMP ddbl_blank              ; near trampoline so the branches above stay in range
.ddbl_gap_expired
    INC bonus_letter            ; gap done -> move to the next lit letter
    LDA bonus_letter
    CMP lit_count
    BCC ddbl_blank_near         ; more letters -> first row of next letter is blank
    JMP ddbl_finished           ; no more letters -> end the bonus round
.ddbl_not_gap
    LDA bonus_step
    BEQ ddbl_draw_row
    DEC bonus_step              ; blank vertical-pitch row
    JMP ddbl_blank_near

.ddbl_draw_row
    ; point at the current letter's bitmap, fetch row bonus_subrow
    LDX bonus_letter
    LDA lit_list,X              ; A = letter index 0..4
    TAX
    LDA bonus_letter_ptr_lo,X : STA copy_ptr_lo
    LDA bonus_letter_ptr_hi,X : STA copy_ptr_hi
    LDY bonus_subrow
    LDA (copy_ptr_lo),Y         ; A = 5-bit row mask
    STA temp2                   ; temp2 = bits still to draw / record
    LDX item_buf_wr
    STA acorn_mask,X            ; collision: this row's acorn columns = the row mask exactly

    LDA #0 : STA temp3          ; temp3 = slot index b (0..4)
.ddbl_bit_loop
    LSR temp2                   ; shift current bit into carry (bit0 first = leftmost)
    BCC ddbl_bit_skip
    LDX temp3
    LDA acorn_slot_col,X
    PHA                         ; column for the bottom cell (DRAWCELL clobbers A)
    DRAWCELL 1, spr_acorn_top
    PLA
    DRAWCELL 2, spr_acorn_bottom
.ddbl_bit_skip
    INC temp3
    LDA temp3
    CMP #5
    BNE ddbl_bit_loop

    ; schedule the next row. bonus_subrow counts DOWN 6->0: the apex (subrow 0) is drawn
    ; last so that after the screen scrolls down the letter reads the right way up.
    LDA #ACORN_ROW_PITCH-1 : STA bonus_step
    LDA bonus_subrow
    BEQ ddbl_letter_done        ; just drew the top row (subrow 0) -> letter finished
    DEC bonus_subrow
    JMP ddbl_blank
.ddbl_letter_done
    LDA #6 : STA bonus_subrow    ; reset for the next letter
    LDA #0 : STA bonus_step      ; gap supplies the blank rows from here
    LDA #ACORN_LETTER_GAP : STA bonus_gap
.ddbl_blank
    JMP dmr_no_name

.ddbl_finished
    LDA season_rows
    STA map_row_idx             ; force map_row_idx >= season_rows so the INC trips bonus_complete
    JMP dmr_no_name

.dmr_no_name

    LDX #LO(vdu_row_clear)
    LDY #HI(vdu_row_clear)
    LDA #7
    JSR send_vdu_seq

    LDA #30
    JSR OSWRCH
    LDA #11
    JSR OSWRCH

    CLC
    LDA scroll_py
    ADC #8
    STA scroll_py

    RINGINC item_buf_wr, 24
    RINGINC item_buf_rd, 24

    LDA #5
    JMP OSWRCH

.proc_checkhit
    LDA transition_phase
    BNE pch_normal              ; during transitions use the normal (item_col) path
    LDA bonus_phase
    BNE pch_bonus               ; bonus round proper uses the per-row acorn-column mask
.pch_normal
    LDX item_buf_rd
    LDA item_col,X
    CMP #&FF
    BNE pch_has_item
    RTS                         ; &FF = no item at this row

; Bonus collision: the row at item_buf_rd may carry several acorns (one per set bit in
; acorn_mask). The caterpillar is 8px = up to two cells wide; collect any acorn whose
; column the caterpillar overlaps, clear that bit, and reuse the acorn erase+score path.
.pch_bonus
    LDX item_buf_rd
    LDA acorn_mask,X
    BNE pcb_has_acorns
    RTS                         ; no acorns on this row
.pcb_has_acorns
    STA temp3                   ; temp3 = row mask
    LDX #0                      ; X = slot index b (0..4)
.pcb_loop
    LDA slot_bit,X
    AND temp3
    BEQ pcb_next                ; this slot has no acorn
    ; same pixel-overlap test the normal acorn path uses (item_col*8 vs cat_px_x)
    LDA acorn_slot_col,X
    ASL A : ASL A : ASL A       ; A = acorn_left_px = col * 8
    STA temp0                   ; temp0 = acorn_left_px
    CLC : ADC #ITEM_R_OFF
    STA temp1                   ; temp1 = acorn_right_px
    LDA cat_px_x
    CLC : ADC #CAT_W-1          ; cat_right
    CMP temp0
    BCC pcb_next                ; cat_right < acorn_left -> miss this slot
    LDA temp1                   ; acorn_right_px
    CMP cat_px_x
    BCS pcb_hit                 ; acorn_right >= cat_left -> overlap
.pcb_next
    INX
    CPX #5
    BNE pcb_loop
    RTS                         ; caterpillar over no acorn this row
.pcb_hit
    ; clear this slot's bit so it can't be collected twice
    LDA slot_bit,X
    EOR #&FF
    STA temp2                   ; temp2 = inverse mask
    LDY item_buf_rd
    LDA acorn_mask,Y
    AND temp2
    STA acorn_mask,Y
    ; reuse the acorn erase + scoring path
    LDA acorn_slot_col,X : STA pch_item_col
    LDA #2 : STA pch_item_type
    JMP pch_clear_sb
.pch_has_item
    STA temp0                   ; item column (cell, left edge) - preserved for dispatch
    LDA item_type,X
    STA temp1                   ; item type (0=mushroom, 1=item, 2=acorn) - preserved

    LDA temp0
    ASL A : ASL A : ASL A       ; item_left_px = item_col * 8
    STA temp2                   ; temp2 = item_left_px
    LDX temp1
    BEQ pch_mush_width          ; type 0 = mushroom (two cells)
    CLC : ADC #ITEM_R_OFF       ; fruit/acorn
    JMP pch_have_right
.pch_mush_width
    CLC : ADC #MUSH_R_OFF       ; mushroom cap spans both cells
.pch_have_right
    STA temp3                   ; temp3 = item_right_px

    LDA cat_px_x
    CLC : ADC #CAT_W-1          ; A = cat_right
    CMP temp2                   ; cat_right vs item_left_px
    BCS pch_test2               ; cat_right >= item_left → still possible
    RTS                         ; cat_right < item_left → miss (near branch target)
.pch_test2
    LDA temp3                   ; item_right_px
    CMP cat_px_x                ; item_right_px vs cat_left
    BCS pch_hit                 ; item_right >= cat_left → overlap
    RTS                         ; item_right < cat_left → miss
.pch_hit
    LDX item_buf_rd
    LDA #&FF : STA item_col,X
    LDA temp1
    BEQ pch_mushroom            ; type 0 = cap → crash (skip erase)
    LDA temp0 : STA pch_item_col
    LDA temp1 : STA pch_item_type
    LDA #0 : LDX #31
.pch_clear_sb
    STA save_buffer,X           ; save_buffer := 32 zero bytes (blank cell)
    DEX
    BPL pch_clear_sb
    LDA pch_item_col : DRAWCELL 24, save_buffer ; black over the fruit's own cell
    LDA pch_item_type
    CMP #2
    BNE pch_dispatch            ; type 1 (fruit) = single cell, done
    LDA pch_item_col : DRAWCELL 25, save_buffer ; acorn: also clear bottom cell (row 25)
    LDA pch_item_type           ; A = item type for dispatch
.pch_dispatch
    CMP #2
    BEQ pch_acorn               
    LDX season
    LDA item_points,X        
    PHA                         
    LDA item_sound_hi,X
    TAY                        
    LDA item_sound_lo,X
    TAX                         ; X = sound block lo
    PLA                         ; A = points
    JMP add_score_and_sound
.pch_mushroom
    LDA collision_on
    BEQ pch_pass                ; C toggled off: pass through mushroom, pickups still score
    JMP proc_crash
.pch_pass
    RTS
.pch_acorn
    LDA acorn_score : CLC : ADC #10 : STA acorn_score
    LDA acorn_score             ; A = acorn points for the score add
    LDX #LO(sound_hit5) : LDY #HI(sound_hit5) ; single flushed note (rapid acorns retrigger)
    JMP add_score_and_sound

.add_score_and_sound
    PHA                         ; save points
    LDA #7
    JSR OSWORD                  ; X/Y already hold sound block address
    PLA
    CLC
    ADC score_lo
    STA score_lo
    LDA score_hi
    ADC #0
    STA score_hi
    RTS

.proc_crash
    LDA hiscore_lo
    CMP score_lo
    LDA hiscore_hi
    SBC score_hi
    BCS pc_no_hiscore           ; hiscore >= score
    LDA score_lo : STA hiscore_lo
    LDA score_hi : STA hiscore_hi
.pc_no_hiscore
    LDA score_lo   : STA saved_score_lo
    LDA score_hi   : STA saved_score_hi
    LDA hiscore_lo : STA saved_hiscore_lo
    LDA hiscore_hi : STA saved_hiscore_hi

    LDA #0
    STA osword_blk
    STA osword_blk+1
    STA osword_blk+5
    STA osword_blk+7
    LDA #&FF
    STA osword_blk+3
    LDA #4
    STA osword_blk+4
    LDA #1
    STA osword_blk+6

    LDA #&F1
.crash_loop
    STA osword_blk+2
    LDA #7
    LDX #LO(osword_blk)
    LDY #HI(osword_blk)
    JSR OSWORD
    JSR vsync_wait
    LDA osword_blk+2
    CLC : ADC #1
    BNE crash_loop              ; Z flag set by ADC when &FF wraps to 0

    LDA #15
    LDX #0
    JSR OSBYTE

    JSR OSRDCH

    LDA #0
    STA game_result
    JMP return_to_basic

.show_completed
    LDA acorn_word
    CMP #&1F                    ; all 5 bits set?
    BNE sc_no_acorn
    CLC
    LDA score_lo
    ADC #LO(1000)
    STA score_lo
    LDA score_hi
    ADC #HI(1000)
    STA score_hi
.sc_no_acorn
    LDA hiscore_lo
    CMP score_lo
    LDA hiscore_hi
    SBC score_hi
    BCS sc_no_hiscore
    LDA score_lo : STA hiscore_lo
    LDA score_hi : STA hiscore_hi
.sc_no_hiscore
    LDA score_lo   : STA saved_score_lo
    LDA score_hi   : STA saved_score_hi
    LDA hiscore_lo : STA saved_hiscore_lo
    LDA hiscore_hi : STA saved_hiscore_hi
    LDA #1
    STA game_result
    JMP return_to_basic

.do_colour
    PHA
    LDA #17 : JSR OSWRCH
    PLA     : JMP OSWRCH

.do_tab
    PHA
    LDA #31 : JSR OSWRCH
    PLA     : JSR OSWRCH
    TXA     : JMP OSWRCH

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

.vsync_wait
    LDA #19
    JMP OSBYTE

.read_key
    LDA #129
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    RTS

.print_string
    STX temp0
    STY temp1
    LDY #0
.ps_loop
    LDA (temp0),Y
    BEQ ps_done
    JSR OSWRCH
    INY
    BNE ps_loop                 ; max 256 chars per string
.ps_done
    RTS

.advance_scanline
    INC temp0
    LDA temp0
    AND #7
    STA temp0
    BNE as_same_row
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

.calc_item_addr
    PHA                         ; save text_col
    TXA
    ASL A : ASL A : ASL A       ; A = text_row * 8
    SEC
    SBC scroll_py               ; physical pixel Y
    LSR A : LSR A : LSR A       ; physical char row (0-31)
    TAX
    LDA row_table_lo,X
    STA scr_addr_lo
    LDA row_table_hi,X
    STA scr_addr_hi
    PLA                         ; restore text_col (0-19)
    TAX                         ; save copy in X
    LSR A : LSR A : LSR A
    CLC
    ADC scr_addr_hi
    STA scr_addr_hi
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

.draw_item
    LDA #8
    STA temp1                   ; row counter
.di_row_loop
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
    CLC
    LDA copy_ptr_lo
    ADC #4
    STA copy_ptr_lo
    BCC di_no_ptr_carry
    INC copy_ptr_hi
.di_no_ptr_carry
    INC scr_addr_lo
    BNE di_no_scr_carry
    INC scr_addr_hi
.di_no_scr_carry
    DEC temp1
    BNE di_row_loop
    RTS

.prep_sprite_addr
    SEC
    LDA cat_px_y
    SBC scroll_py
    STA temp2                   ; physical Y for calc_screen_addr
    JSR calc_screen_addr
    LDA temp2
    AND #7
    STA temp0                   ; starting scanline
    RTS

.calc_screen_addr
    LDA temp2
    LSR A
    LSR A
    LSR A                       ; A = char_row (0-31)
    TAX
    LDA row_table_lo,X
    STA scr_addr_lo
    LDA row_table_hi,X
    STA scr_addr_hi

    LDA cat_px_x
    LSR A                       ; byte_col
    STA temp0                   ; save byte_col for high byte calc
    ASL A
    ASL A
    ASL A                       ; low byte of byte_col * 8 (overflow into carry)
    CLC
    ADC scr_addr_lo
    STA scr_addr_lo
    LDA scr_addr_hi
    ADC #0
    STA scr_addr_hi
    LDA temp0
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    CLC
    ADC scr_addr_hi
    STA scr_addr_hi

    LDA temp2
    AND #7
    CLC
    ADC scr_addr_lo
    STA scr_addr_lo
    LDA scr_addr_hi
    ADC #0
    STA scr_addr_hi

    RTS

.save_background
    LDX #0                      ; buffer index
    LDA #8                      ; row counter
    STA temp1
.sb_row_loop
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

.draw_sprite

.draw_sprite_even
    LDX #0                      ; sprite data index
    LDA #8
    STA temp1                   ; row counter
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

.vdu_init_data                  ; MODE 2 + cursor off + VDU 5
    EQUB 22, 2, 23, 0, 10, 32, 0, 0, 0, 0, 0, 0, 5
.vdu_row_clear                  ; VDU 28,0,30,19,30 + CLS + restore window
    EQUB 28, 0, 30, 19, 30, 12, 26

.collision_on
    EQUB 1                      ; 1=collision active, 0=disabled
.collision_key_prev
    EQUB 0                      ; previous C key state (for edge detection)

.col_offset       EQUB 0        ; column offset for current season (0-19)
.item_skip        EQUB 0        ; skip every Nth mushroom (0=none, 2=every 2nd, 3=every 3rd)
.item_counter     EQUB 0        ; counts up, resets at item_skip

; --- Bonus-round "spell ACORN in falling acorns" state (only used while bonus_phase=1) ---
; Each lit letter is drawn as a 5-acorn-wide x 7-row mosaic, one letter at a time, with
; gaps between acorns (3-cell column pitch, 4-row pitch) so the giant letter reads clearly.
.lit_list         SKIP 5        ; ordered indices (0=A..4=N) of the letters the player lit
.lit_count        EQUB 0        ; how many letters are in lit_list
.bonus_letter     EQUB 0        ; index into lit_list of the letter currently falling
.bonus_subrow     EQUB 0        ; which of the 7 letter-rows is being emitted next (0-6)
.bonus_step       EQUB 0        ; sub-step counter within a letter-row (0=draw, 1-3=blank pitch)
.bonus_gap        EQUB 0        ; blank-row countdown separating one letter from the next

.save_buffer
    SKIP 32

.body_scr_lo
    SKIP BODY_MAX
.body_scr_hi
    SKIP BODY_MAX
.body_scanln
    SKIP BODY_MAX

.body_save_base
    SKIP 32 * BODY_MAX

.item_col
    SKIP 24
.item_type
    SKIP 24
.acorn_mask
    SKIP 24                      ; bonus only: per-row 5-bit mask of which acorn columns are present
                                ; (bit b set => an acorn sits at playfield col ACORN_BOX_LEFT + b*3)

.body_buf_addr_lo
FOR i, 0, BODY_MAX - 1
    EQUB LO(body_save_base + i * 32)
NEXT
.body_buf_addr_hi
FOR i, 0, BODY_MAX - 1
    EQUB HI(body_save_base + i * 32)
NEXT

.spr_caterpillar
    EQUB &2A, &01, &02, &15
    EQUB &04, &01, &02, &08
    EQUB &00, &01, &02, &00
    EQUB &0F, &01, &02, &0F
    EQUB &04, &01, &02, &08
    EQUB &0F, &01, &02, &0F
    EQUB &04, &01, &02, &08
    EQUB &0F, &01, &02, &0F

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
    EQUB &00,&00,&00,&00

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

.item_spr_lo
    EQUB LO(spr_leaf), LO(spr_snow), LO(spr_flower), LO(spr_apple)
.item_spr_hi
    EQUB HI(spr_leaf), HI(spr_snow), HI(spr_flower), HI(spr_apple)

.item_points
    EQUB 5, 10, 15, 20          ; autumn=5, winter=10, spring=15, summer=20
.item_sound_lo
    EQUB LO(sound_hit1), LO(sound_hit2), LO(sound_hit3), LO(sound_hit4)
.item_sound_hi
    EQUB HI(sound_hit1), HI(sound_hit2), HI(sound_hit3), HI(sound_hit4)

.sound_hit1
    EQUW 1, 1, 60, 4

.sound_hit2
    EQUW 1, 1, 80, 4

.sound_hit3
    EQUW 1, 1, 100, 4

.sound_hit4
    EQUW 1, 1, 120, 4

.sound_hit5
    EQUW &11, 2, 120, 3         ; &11 = flush channel 1 first, so rapid bonus acorns retrigger
                                ; instead of queueing (OSWORD 7 would otherwise BLOCK when full)

.sound_tick
    EQUW 0, -2, 4, 1

.sound_letter
    EQUW 1, 2, 200, 4

.sound_celebrate
    EQUW 1, 2, 250, 12

.envelope_data
    EQUB 1                      ; envelope number
    EQUB 1                      ; step length (10ms per step)
    EQUB -6                     ; pitch section 1: descend
    EQUB 0                      ; pitch section 2: hold
    EQUB 0                      ; pitch section 3: hold
    EQUB 8                      ; steps in section 1
    EQUB 0                      ; steps in section 2
    EQUB 0                      ; steps in section 3
    EQUB 126                    ; attack change (fast rise)
    EQUB -16                    ; decay change
    EQUB 0                      ; sustain change
    EQUB -16                    ; release change
    EQUB 126                    ; attack target
    EQUB 0                      ; decay target

.envelope2_data
    EQUB 2                      ; envelope number
    EQUB 1                      ; step length (10ms per step)
    EQUB 8                      ; pitch section 1: ascend
    EQUB -4                     ; pitch section 2: slow descend
    EQUB 0                      ; pitch section 3: hold
    EQUB 5                      ; steps in section 1 (rise 40 over 50ms)
    EQUB 10                     ; steps in section 2 (fall 40 over 100ms)
    EQUB 0                      ; steps in section 3
    EQUB 126                    ; attack change (fast rise)
    EQUB -4                     ; decay change (slow fade)
    EQUB 0                      ; sustain change
    EQUB -8                     ; release change
    EQUB 126                    ; attack target
    EQUB 0                      ; decay target

.season_config
    EQUB LO(map_base), HI(map_base), 64, 2, 5, 2 ; Autumn: ~17 mush (50%), offset 5
    EQUB LO(map_base), HI(map_base), 64, 2, 10, 3 ; Winter: ~22 mush (67%), offset 10
    EQUB LO(map_base), HI(map_base), 64, 2, 15, 4 ; Spring: ~25 mush (75%), offset 15
    EQUB LO(map_base), HI(map_base), 64, 2, 0, 0 ; Summer: 33 mush (100%), no offset

;   &00-&13: mushroom at column 0-19
;   &20-&33: season item at column 0-19
;   &40-&53: acorn at column 0-19

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

; Giant-letter bitmaps for the bonus round. 5 letters (A,C,O,R,N), 7 rows each.
; Each row byte holds a 5-bit mask: bit b set => an acorn at playfield col 4 + b*3.
; bit0 = leftmost column (4), bit4 = rightmost column (16). Shapes are drawn spaced
; out so each acorn has clear air around it.
.bonus_letter_rows
.bl_A
    EQUB %01110, %10001, %10001, %11111, %10001, %10001, %10001
.bl_C
    EQUB %01110, %10001, %00001, %00001, %00001, %10001, %01110
.bl_O
    EQUB %01110, %10001, %10001, %10001, %10001, %10001, %01110
.bl_R
    EQUB %01111, %10001, %10001, %01111, %00101, %01001, %10001
.bl_N
    EQUB %10001, %10011, %10101, %11001, %10001, %10001, %10001
.bonus_letter_ptr_lo
    EQUB LO(bl_A), LO(bl_C), LO(bl_O), LO(bl_R), LO(bl_N)
.bonus_letter_ptr_hi
    EQUB HI(bl_A), HI(bl_C), HI(bl_O), HI(bl_R), HI(bl_N)
; Playfield column of each of the 5 acorn slots (= ACORN_BOX_LEFT + b*ACORN_BOX_PITCH).
.acorn_slot_col
    EQUB 4, 7, 10, 13, 16
.slot_bit
    EQUB 1, 2, 4, 8, 16         ; bit mask for each acorn slot (1<<b)

.season_name_lo
    EQUB LO(str_autumn), LO(str_winter), LO(str_spring), LO(str_summer), LO(str_bonus)
.season_name_hi
    EQUB HI(str_autumn), HI(str_winter), HI(str_spring), HI(str_summer), HI(str_bonus)
.acorn_target_col
    EQUB 4, 4, 13, 11, 6        ; target columns spelling ACORN (A=4,C=4,O=13,R=11,N=6)
.acorn_bit_table
    EQUB 1, 2, 4, 8, 16         ; bit masks for acorn_word (one per season)
.acorn_col_table
    EQUB 10, 3, 16, 7           ; rotating acorn columns (spread across playfield)

.str_autumn
    EQUS "Autumn Fall", 0
.str_winter
    EQUS "Cold Winter", 0
.str_spring
    EQUS "Spring Bloom", 0
.str_summer
    EQUS "Summer Rays", 0
.str_bonus
    EQUS "Bonus Bunch", 0

.end

SAVE "GAME", start, end, start
PUTBASIC "caterpillar.bas", "CATER"
PUTTEXT "!BOOT", "!BOOT", &FFFF
