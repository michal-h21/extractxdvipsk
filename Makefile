All:  sample.pdf sample.html sample.dvi 

sample.pdf: sample.tex
	lualatex $<

sample.dvi: sample.tex usepackage-fontspec.4ht config.cfg
	make4ht -a debug -ulm draft -n -f html5+detect_engine -c config.cfg $<

sample.html: sample.dvi extractdvipsk.lua
	rm .xdvipsk/*
	texlua extractdvipsk.lua $<
	tex4ht-vtex -utf8 -cmozhtf $<
	t4ht $<
	
