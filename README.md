# extractdvipsk.lua

# Introduction

Known issue for `TeX4ht`, tool for TeX to XML conversion is that it doesn't
have native support for OpenType fonts. We were able to work around this issue,
so it is still possible to use multi lingual documents using LuaTeX or XeTeX.

Recently, the [fixed version](https://github.com/mingiss/tex4ht-vtex) of
`tex4ht`  -- command used for the actual conversion -- that can support the
OpenType fonts had been developed. It uses files that provide mapping between glyphs
used in a OpenType font and Unicode characters.

The `extractdvipsk.lua` script can detect fonts requested in the DVI file and
create necessary mapping files.

# Usage

Run command

    texlua extractdvipsk.lua <filename.dvi>

The mappings will be placed in the `.xdvipsk/` subdirectory.

This repository contains sample TeX file. Run the `make` command to compile it.

# Technical details

`extractdvipsk.lua` depends on font name database and cached font tables
provided by Luaotfload. It is necessary to compile the TeX document using
LuaLaTeX first when a new font is used.

This script creates a `.xdvipsk/` subdirectory in the current directory. 

# Issues

This is still work in progress and mainly used for testing. It is not production ready yet. There are many issues:

- spaces are not detected for some fonts
- Unicode codepoints between 128 and 255 are not correctly translated to UTF-8
- it is possible that some glyphs have no mapping back to Unicode, so they will be missing in the converted document
- characters `<`, `>` and `&` are not escaped to HTML entities when used in OpenType fonts
