* cat - concatinate
*
* Itagaki Fumihiko 19-Jun-91  Create.
* 1.0
* Itagaki Fumihiko 27-Jan-93  Zap.
* 1.2
* Itagaki Fumihiko 07-Feb-93  ファイル引数に過剰な / があれば除去する
* 1.3
* Itagaki Fumihiko 19-Feb-93  標準入力が切り替えられていても端末から^Cや^Sなどが効くようにした
* 1.4
*
* Usage: cat [ -nbsvetmqBCZ ] [ <ファイル> | - ] ...
*

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref iscntrl
.xref utoa
.xref strlen
.xref strcmp
.xref strfor1
.xref printfi
.xref strip_excessive_slashes

STACKSIZE	equ	2048

INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED	equ	8192
OUTBUF_SIZE	equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_process	equ	0
FLAG_n		equ	1	*  -n
FLAG_b		equ	2	*  -b
FLAG_s		equ	3	*  -s
FLAG_v		equ	4	*  -v
FLAG_e		equ	5	*  -e
FLAG_t		equ	6	*  -t
FLAG_m		equ	7	*  -m
FLAG_q		equ	8	*  -q
FLAG_B		equ	9	*  -B
FLAG_C		equ	10	*  -C
FLAG_Z		equ	11	*  -Z

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bsstop(pc),a6			*  A6 := BSSの先頭アドレス
		lea	stack_bottom(a6),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin(a6)
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		moveq	#0,d6				*  D6.W : エラー・コード
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		subq.l	#1,d0
		bne	decode_opt_start

		lea	word_fish(pc),a1
		bsr	strcmp
		beq	cat_fish
decode_opt_start:
		moveq	#0,d5				*  D5.L : フラグbits
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		moveq	#FLAG_n,d1
		cmp.b	#'n',d0
		beq	set_option_with_process

		moveq	#FLAG_b,d1
		cmp.b	#'b',d0
		beq	set_option_with_process

		moveq	#FLAG_s,d1
		cmp.b	#'s',d0
		beq	set_option_with_process

		moveq	#FLAG_v,d1
		cmp.b	#'v',d0
		beq	set_option_with_process

		moveq	#FLAG_e,d1
		cmp.b	#'e',d0
		beq	set_option_with_process

		moveq	#FLAG_t,d1
		cmp.b	#'t',d0
		beq	set_option_with_process

		moveq	#FLAG_m,d1
		cmp.b	#'m',d0
		beq	set_option_with_process

		moveq	#FLAG_q,d1
		cmp.b	#'q',d0
		beq	set_option

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

option_B_found:
		bset	#FLAG_B,d5
		bclr	#FLAG_C,d5
		bra	set_option_done

option_C_found:
		bset	#FLAG_C,d5
		bclr	#FLAG_B,d5
		bra	set_option_done

set_option_with_process:
		bset	#FLAG_process,d5		*  即時write不可
set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering
		beq	input_max			*  -- block device

		*  character device
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	input_max

		*  cooked character device
		move.l	#INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED,d0
		btst	#FLAG_B,d5
		bne	inpbufsize_ok

		bset	#FLAG_C,d5			*  改行を変換する
		bra	inpbufsize_ok

input_max:
		move.l	#$00ffffff,d0
inpbufsize_ok:
		move.l	d0,inpbuf_size(a6)

		*  process を fix する
		btst	#FLAG_C,d5
		beq	set_process_ok

		bset	#FLAG_process,d5
set_process_ok:
		*  do_buffering を fix する
		btst	#FLAG_process,d5
		bne	set_buffering_ok

		sf	do_buffering
set_buffering_ok:
		*  出力バッファを確保する
		tst.b	do_buffering
		beq	outbuf_ok

		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top
		move.l	d0,outbuf_ptr
outbuf_ok:
		*  入力バッファを確保する
		move.l	inpbuf_size(a6),d0
		bsr	malloc
		bpl	inpbuf_ok

		sub.l	#$81000000,d0
		move.l	d0,inpbuf_size(a6)
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf_top(a6)
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin(a6)
		bmi	start_do_files

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
start_do_files:
	*
	*  開始
	*
		clr.l	lineno(a6)
		st	newline(a6)
		sf	pending_cr(a6)
		sf	last_is_empty(a6)
		tst.l	d7
		beq	do_stdin
for_file_loop:
		subq.l	#1,d7
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		cmpi.b	#'-',(a0)
		bne	do_file

		tst.b	1(a0)
		bne	do_file
do_stdin:
		lea	msg_stdin(pc),a0
		move.l	stdin(a6),d2
		bmi	open_file_failure

		bsr	cat_one
		bra	for_file_continue

do_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		move.l	d0,d2
		bmi	open_file_failure

		bsr	cat_one
		move.w	d2,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
for_file_continue:
		movea.l	a1,a0
		tst.l	d7
		bne	for_file_loop

		bsr	flush_outbuf
exit_program:
		move.l	stdin(a6),d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

open_file_failure:
		moveq	#2,d6
		btst	#FLAG_q,d5
		bne	for_file_continue

		bsr	werror_myname_and_msg
		lea	msg_open_fail(pc),a0
		bsr	werror
		bra	for_file_continue
****************************************************************
cat_fish:
		pea	msg_catfish(pc)
		DOS	_PRINT
		addq.l	#4,a7
		bra	exit_program
****************************************************************
* cat_one
****************************************************************
cat_one:
		btst	#FLAG_Z,d5
		sne	terminate_by_ctrlz(a6)
		sf	terminate_by_ctrld(a6)
		move.w	d2,d0
		bsr	is_chrdev
		beq	cat_one_start			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	cat_one_start

		st	terminate_by_ctrlz(a6)
		st	terminate_by_ctrld(a6)
cat_one_start:
		movea.l	inpbuf_top(a6),a3
cat_one_loop:
		move.l	inpbuf_size(a6),-(a7)
		move.l	a3,-(a7)
		move.w	d2,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d3
		bmi	read_fail

		sf	d4				* D4.B : EOF flag
		tst.b	terminate_by_ctrlz(a6)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	terminate_by_ctrld(a6)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		tst.l	d3
		beq	cat_one_done

		btst	#FLAG_process,d5
		bne	cat_one_do_process

		move.l	d3,-(a7)
		move.l	a3,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	d3,d0
		blo	write_fail

		bra	cat_one_continue

cat_one_do_process:
		movea.l	a3,a2
write_loop:
		move.b	(a2)+,d0
		*
		*	if (newline) {
		*		if (!pending_cr && code == CR) goto do_pending_cr;
		*		tmp = last_is_empty;
		*		last_is_empty = (code == LF);
		*		if (last_is_empty && tmp && FLAG_s) {
		*			pending_cr = 0;
		*			continue;
		*		}
		*		newline = 0;
		*		print_lineno(++lineno);
		*	}
		tst.b	newline(a6)
		beq	continue_for_line

		tst.b	pending_cr(a6)
		bne	check_empty

		cmp.b	#CR,d0
		beq	do_pending_cr
check_empty:
		move.b	last_is_empty(a6),d1
		cmp.b	#LF,d0
		seq	last_is_empty(a6)
		bne	not_cancel_line

		tst.b	d1
		beq	not_cancel_line

		btst	#FLAG_s,d5
		beq	not_cancel_line

		sf	pending_cr(a6)
		bra	write_continue

not_cancel_line:
		sf	newline(a6)

		btst	#FLAG_b,d5
		beq	not_b

		tst.b	last_is_empty(a6)
		bne	continue_for_line
		bra	print_lineno

not_b:
		btst	#FLAG_n,d5
		beq	continue_for_line
print_lineno:
		addq.l	#1,lineno(a6)
		movem.l	d0-d4/a0-a2,-(a7)
		move.l	lineno(a6),d0
		moveq	#0,d1
		moveq	#' ',d2
		moveq	#6,d3
		moveq	#1,d4
		lea	utoa(pc),a0
		lea	putc(pc),a1
		suba.l	a2,a2
		bsr	printfi
		moveq	#HT,d0
		bsr	putc
		movem.l	(a7)+,d0-d4/a0-a2
continue_for_line:
		*	if (code == LF) {
		*		if (FLAG_e) putc('$');
		*		if (FLAG_C) pending_cr = 1;
		*		flush_cr();
		*		newline = 1;
		*	}
		*	else {
		*		flush_cr();
		*		if (code == CR) {
		*			pending_cr = 1;
		*			continue;
		*		}
		*		else ...
		*			:
		*			:
		*			:
		*	}
		*	putc(code);
		*
		cmp.b	#LF,d0
		bne	not_lf

		btst	#FLAG_e,d5
		beq	pass_put_doller

		move.w	d0,-(a7)
		moveq	#'$',d0
		bsr	putc
		move.w	(a7)+,d0
pass_put_doller:
		btst	#FLAG_C,d5
		beq	pass_convert_newline

		st	pending_cr(a6)
pass_convert_newline:
		bsr	flush_cr
		st	newline(a6)
		bra	put1char_normal

not_lf:
		bsr	flush_cr
		cmp.b	#CR,d0
		bne	not_cr
do_pending_cr:
		st	pending_cr(a6)
		bra	write_continue

not_cr:
		cmp.b	#HT,d0
		beq	put_ht

		cmp.b	#FS,d0
		beq	put1char_normal

		btst	#7,d0
		beq	put1char_nonmeta

		btst	#FLAG_m,d5
		beq	put1char_nonmeta

		move.w	d0,-(a7)
		moveq	#'M',d0
		bsr	putc
		moveq	#'-',d0
		bsr	putc
		move.w	(a7)+,d0
		bclr	#7,d0
put1char_nonmeta:
		bsr	iscntrl
		bne	put1char_normal

		btst	#FLAG_v,d5
		bne	put_cntrl_caret

		btst	#FLAG_e,d5
		bne	put_cntrl_caret

		btst	#FLAG_t,d5
		bne	put_cntrl_caret

		btst	#FLAG_m,d5
		bne	put_cntrl_caret

		bra	put1char_normal

put_ht:
		btst	#FLAG_t,d5
		beq	put1char_normal
put_cntrl_caret:
		move.w	d0,-(a7)
		moveq	#'^',d0
		bsr	putc
		move.w	(a7)+,d0
		add.b	#$40,d0
		bclr	#7,d0
put1char_normal:
		bsr	putc
write_continue:
		subq.l	#1,d3
		bne	write_loop
cat_one_continue:
		tst.b	d4
		beq	cat_one_loop
cat_one_done:
flush_cr:
		tst.b	pending_cr(a6)
		beq	flush_cr_done

		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		move.l	(a7)+,d0
		sf	pending_cr(a6)
flush_cr_done:
		rts
*****************************************************************
trunc:
		move.l	d3,d1
		beq	trunc_done

		movea.l	a3,a2
trunc_find_loop:
		cmp.b	(a2)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		move.l	a2,d3
		subq.l	#1,d3
		sub.l	a3,d3
		st	d4
trunc_done:
		rts
*****************************************************************
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering
		beq	flush_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free,d0
		beq	flush_return

		move.l	d0,-(a7)
		move.l	outbuf_top,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		move.l	outbuf_top,d0
		move.l	d0,outbuf_ptr
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
flush_return:
		move.l	(a7)+,d0
		rts
*****************************************************************
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_buffering:
		tst.l	outbuf_free
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_ptr,a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr
		subq.l	#1,outbuf_free
putc_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
insufficient_memory:
		bsr	werror_myname
		lea	msg_no_memory(pc),a0
		bra	werror_exit_3
*****************************************************************
read_fail:
		bsr	werror_myname_and_msg
		lea	msg_read_fail(pc),a0
		bra	werror_exit_3
*****************************************************************
write_fail:
		lea	msg_write_fail(pc),a0
werror_exit_3:
		bsr	werror
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## cat 1.4 ##  Copyright(C)1991-93 by Itagaki Fumihiko',0

msg_myname:		dc.b	'cat: ',0
word_fish:		dc.b	'-fish',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'cat: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_usage:		dc.b	CR,LF,'使用法:  cat [-nbsvetmqBCZ] [--] [<ファイル>] ...',CR,LF,0
msg_catfish:		dc.b	'catfish n.【魚】なまず.',CR,LF,0
*****************************************************************
.bss
.even
* これらはputcで参照されるので abs data でなければならない
outbuf_top:		ds.l	1
outbuf_ptr:		ds.l	1
outbuf_free:		ds.l	1
do_buffering:		ds.b	1
.even
bsstop:
.offset 0
inpbuf_top:		ds.l	1
inpbuf_size:		ds.l	1
lineno:			ds.l	1
stdin:			ds.l	1
terminate_by_ctrlz:	ds.b	1
terminate_by_ctrld:	ds.b	1
newline:		ds.b	1
pending_cr:		ds.b	1
last_is_empty:		ds.b	1

		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
