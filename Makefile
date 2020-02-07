All:  sample.html sample.pdf sample.dvi

sample.pdf: sample.tex
	lualatex-dev $<

sample.dvi: sample.tex usepackage-fontspec.4ht
	make4ht -a debug -ulm draft -n -f html5+detect_engine -c config.cfg $<

sample.html: sample.dvi extractdvipsk.lua
	rm .xdvipsk/*
	texlua extractdvipsk.lua $<
	tex4ht-vtex -utf8 -cmozhtf $<
	t4ht $<
	
