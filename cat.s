* cat - concatinate
*
* Itagaki Fumihiko 19-Jun-91  Create.
*
* Usage: cat [ -CFZunbsvetmq ] [ - | <ファイル> ] ...
*

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref iscntrl
.xref utoa
.xref strlen
.xref strfor1
.xref printfi
.xref tfopen
.xref fclose

STACKSIZE	equ	512

INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED	equ	8192
OUTBUF_SIZE	equ	1024

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_complex	equ	0
FLAG_C		equ	1	*  -c
FLAG_F		equ	2	*  -f
FLAG_Z		equ	3	*  -z
FLAG_u		equ	4	*  -u （出力がキャラクタ・デバイスのときは常にON）
FLAG_n		equ	5	*  -n
FLAG_b		equ	6	*  -b
FLAG_s		equ	7	*  -s
FLAG_v		equ	8	*  -v
FLAG_e		equ	9	*  -e
FLAG_t		equ	10	*  -t
FLAG_m		equ	11	*  -m
FLAG_q		equ	12	*  -q


.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bsstop(pc),a6			*  A6 := BSSの先頭アドレス
		lea	stack_bottom(a6),a7		*  A7 := スタックの底
		DOS	_GETPDB
		movea.l	d0,a0				*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
		bsr	DecodeHUPAIR			*  デコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d6				*  D6.W : エラー・コード
		moveq	#0,d5				*  D5.L : フラグbits
parse_option:
		tst.l	d7
		beq	parse_option_done

		cmpi.b	#'-',(a0)
		bne	parse_option_done

		tst.b	1(a0)
		beq	parse_option_done

		addq.l	#1,a0
		subq.l	#1,d7
parse_option_arg:
		move.b	(a0)+,d0
		beq	parse_option

		cmp.b	#'C',d0
		beq	option_c_found

		cmp.b	#'F',d0
		beq	option_f_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	option_found_1

		moveq	#FLAG_u,d1
		cmp.b	#'u',d0
		beq	option_found_1

		moveq	#FLAG_n,d1
		cmp.b	#'n',d0
		beq	option_found_2

		moveq	#FLAG_b,d1
		cmp.b	#'b',d0
		beq	option_found_2

		moveq	#FLAG_s,d1
		cmp.b	#'s',d0
		beq	option_found_2

		moveq	#FLAG_v,d1
		cmp.b	#'v',d0
		beq	option_found_2

		moveq	#FLAG_e,d1
		cmp.b	#'e',d0
		beq	option_found_2

		moveq	#FLAG_t,d1
		cmp.b	#'t',d0
		beq	option_found_2

		moveq	#FLAG_m,d1
		cmp.b	#'m',d0
		beq	option_found_2

		moveq	#FLAG_q,d1
		cmp.b	#'q',d0
		beq	option_found_1

		move.w	d0,-(a7)
		bsr	werror_myname
		lea	msg_illegal_option(pc),a0
		bsr	werror
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

option_c_found:
		bset	#FLAG_C,d5
		bclr	#FLAG_F,d5
		bra	parse_option_arg

option_f_found:
		bset	#FLAG_F,d5
		bclr	#FLAG_C,d5
		bra	parse_option_arg

option_found_2:
		bset	#FLAG_complex,d5		*  即時write不可
option_found_1:
		bset	d1,d5
		bra	parse_option_arg

parse_option_done:
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		beq	stdout_is_block_device		*  -- ブロック・デバイスである
	*
	*  出力はキャラクタ・デバイス
	*
		sf	do_buffering			*  バッファリングしない
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	malloc_max_for_input

		move.l	#INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED,d0
		btst	#FLAG_F,d5
		bne	malloc_inpbuf

		bset	#FLAG_C,d5			*  改行を変換する
		bset	#FLAG_complex,d5		*  即時writeできない
		bra	malloc_inpbuf

stdout_is_block_device:
	*
	*  stdoutはブロック・デバイス
	*
		bset	#FLAG_complex,d5		*  単純writeしない
		btst	#FLAG_u,d5
		seq	do_buffering
		bne	malloc_max_for_input

		*  出力バッファを確保する
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top
		move.l	d0,outbuf_ptr
malloc_max_for_input:
		move.l	#$00ffffff,d0
malloc_inpbuf:
		*  入力バッファを確保する
		move.l	d0,inpbuf_size(a6)
		bsr	malloc
		bpl	inpbuf_ok

		sub.l	#$81000000,d0
		move.l	d0,inpbuf_size(a6)
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf_top(a6)
		clr.l	lineno(a6)
		st	newline(a6)
		sf	pending_cr(a6)
		sf	last_is_empty(a6)
		tst.l	d7
		bne	for_file_loop

		bsr	do_stdin
		bra	for_file_done

for_file_loop:
		cmpi.b	#'-',(a0)
		bne	open_file

		tst.b	1(a0)
		bne	open_file

		bsr	do_stdin
		bra	for_file_continue

open_file:
		moveq	#0,d0
		bsr	tfopen
		bpl	open_file_ok

		moveq	#2,d6
		btst	#FLAG_q,d5
		bne	for_file_continue

		bsr	werror_myname
		bsr	werror
		move.l	a0,-(a7)
		lea	msg_open_fail(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		bra	for_file_continue

open_file_ok:
		move.w	d0,d2
		sf	this_is_stdin(a6)
		bsr	do_file
		move.w	d2,d0
		bsr	fclose
for_file_continue:
		bsr	strfor1
		subq.l	#1,d7
		bne	for_file_loop
for_file_done:
		bsr	flush_outbuf
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2
****************************************************************
* do_stdin
* do_file
****************************************************************
do_stdin:
		moveq	#0,d2
		st	this_is_stdin(a6)
do_file:
		btst	#FLAG_Z,d5
		sne	terminate_by_ctrlz(a6)
		sf	terminate_by_ctrld(a6)
		move.w	d2,d0
		bsr	is_chrdev
		beq	do_file_start			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	do_file_start

		st	terminate_by_ctrlz(a6)
		st	terminate_by_ctrld(a6)
do_file_start:
		movea.l	inpbuf_top(a6),a3
do_file_loop:
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
		beq	do_file_done

		btst	#FLAG_complex,d5
		bne	do_file_complex

		move.l	d3,-(a7)
		move.l	a3,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	d3,d0
		blt	write_fail

		bra	do_file_continue

do_file_complex:
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
do_file_continue:
		tst.b	d4
		beq	do_file_loop
do_file_done:
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
		blt	write_fail

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
		bne	putc_do_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_do_buffering:
		tst.l	outbuf_free
		bne	putc_do_buffering_1

		bsr	flush_outbuf
putc_do_buffering_1:
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
		bsr	werror_myname
		tst.b	this_is_stdin(a6)
		beq	read_fail_1

		lea	msg_stdin(pc),a0
read_fail_1:
		bsr	werror
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
	dc.b	'## cat 1.2 ##  Copyright(C)1991 by Itagaki Fumihiko',0

msg_myname:		dc.b	'cat: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'cat: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'(標準入力)',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_usage:		dc.b	CR,LF,'使用法:  cat [ -qcfzunbsvetm ] [ - | <ファイル> ] ...',CR,LF,0
*****************************************************************
.bss
.even
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
this_is_stdin:		ds.b	1
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
