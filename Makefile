# Makefile for ITA TOOLBOX #? cat

AS	= \usr\pds\HAS.X -i $(INCLUDE)
LK	= \usr\pds\hlk.x -x
CV      = -\bin\CV.X -r
INSTALL = cp -puv
BACKUP  = cp -auv
CP      = cp
RM      = -rm -f

INCLUDE = $(HOME)/fish/include

DESTDIR   = A:\usr\ita
BACKUPDIR = B:/cat/1.2

EXTLIB = $(HOME)/fish/lib/ita.l

###

PROGRAM = cat.x

###

.PHONY: all clean clobber install backup

.TERMINAL: *.h *.s

%.r : %.x	; $(CV) $<
%.x : %.o	; $(LK) $< $(EXTLIB)
%.o : %.s	; $(AS) $<

###

all:: $(PROGRAM)

clean::

clobber:: clean
	$(RM) *.bak *.$$* *.o *.x

###

$(PROGRAM) : $(INCLUDE)/doscall.h $(INCLUDE)/chrcode.h $(EXTLIB)

install::
	$(INSTALL) $(PROGRAM) $(DESTDIR)

backup::
	fish -fc '$(BACKUP) * $(BACKUPDIR)'

clean::
	$(RM) $(PROGRAM)

###
