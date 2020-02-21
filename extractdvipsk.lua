kpse.set_program_name "luatex"

require "lualibs"

local xdvipsk_dir = ".xdvipsk"

local wdt_fact = 786.432

local rshift = bit32.rshift
local f_single = function(x) return string.format("%04X", x) end
local f_double = function(x,y) return string.format("%04X%04X", x,y) end
local function hash(k)
  local v
  if k < 0xD7FF or (k > 0xDFFF and k <= 0xFFFF) then
    v = f_single(k)
  elseif k > 191 and k < 256 then
    v = string.format("C3%02X", k - 64)
  else
    local k = k - 0x10000
    v = f_double(rshift(k,10)+0xD800,k%1024+0xDC00)
  end
  return v
end
local unknown = 0

local function tounicode(k)
    if type(k) == "table" then
        local n = #k
        for l=1,n do
            conc[l] = hash[k[l]]
        end
        return concat(conc,"",1,n)
    elseif k >= 0x00E000 and k <= 0x00F8FF then
        return unknown
    elseif k >= 0x0F0000 and k <= 0x0FFFFF then
        return unknown
    elseif k >= 0x100000 and k <= 0x10FFFF then
        return unknown
    else
        return hash( k )
    end
end

local function get_mappings(cachefile)
  -- find mappings between OpenType font names
  -- and the file location
  -- read luaotfload cache
  fontlist = dofile(cachefile)
  local mapping = {}
  -- mapping from font basename to plain name
  -- it seems that enhanced tex4ht neeeds that
  local fontnames = {}
  for _, x in ipairs(fontlist.mappings) do
    --- mapping between font name and file path
    mapping[x.fullname] = x.fullpath
    local fontname = x.basename --:gsub("%..-$", "")
    fontnames[fontname] = x.fullname
  end
  return mapping, fontnames
end

local function normalize_font_name(font)
  -- normalize font name
  font = font:gsub("/(.)$", function(x) 
    local replaces = {B="Bold", I="Italic", BI="BoldItalic"}
    if replaces[x] then return " " .. replaces[x] end
  end)
  -- remove spaces and other symbols
  font = font:gsub("[%s%-%_]", "")
  -- make string lower case
  font = string.lower(font)
  return font
end

local function get_fonts(dvi_file, mapping, fontnames)
  -- find fonts used in the DVI file
  local used_fonts = {}
  local font_map = {}
  local dviasm = io.popen("dviinfox ".. dvi_file)
  local fntdef_found = false -- we don't want to parse the full DVI file
  for line in dviasm:lines() do
    -- opentype fonts are in quotes
    local font = line:match("Font.-:%s+(.+) at")
    if font then
      local orig_font = font -- save the current font for later use
      fntdef_found = true
      if font:match("^\"") then
        -- plainname is used
        font = font:match('"(.-)"')
        orig_font = orig_font:gsub("%s*%(.+%)%s*$", "")-- we must remove stuff in (brackets) at the end
      elseif font:match("^%[") then
        -- basename is used
        font = font:match("%[(.-)%]")
      elseif font:match("%:") then
        local name_parts = font:explode(":")
        if name_parts[1] == "file" then 
          -- we have font file name, this needs to be translated
          -- to font name. The font name will be translated to path to font file later.
          font = fontnames[name_parts[2]]
        elseif name_parts[1] == "name" then
          font = name_parts[2] -- name:font name schema
        else
          font = name_parts[1] -- font name is first part
        end

      end
      if font then
        -- fix font style modifiers
        font = normalize_font_name(font)
        local font_path = mapping[font] or mapping[font.. "regular"] --
        if  font_path then
          used_fonts[font] = font_path
          print(orig_font, font, font_path)
          font_map[font_path] = {dvi_name = orig_font, path = font_path}
        end
      end
    elseif fntdef_found then
      -- break the processing after we had read all fntdefs
      break
    end
  end
  return used_fonts, font_map
end

local function update_font_map_raw(entry, path, metrics)
  -- local entry = font_map[path]
  entry.psname = metrics.fontname
  entry.fullname = metrics.fullname
  -- make default subfamily
  metrics.names = metrics.names or {{names={subfamily="regular"}}}
  entry.subfamily = metrics.names[1].names.subfamily
  entry.path = path
end

local function process_raw_font(fontname, path, entry)
  -- get font characters and information from LuaTeX's fontloader library
  -- it is possible that it will be removed in the future, so this method
  -- is used only if fetching of the font information from Luaotfload cache fails
  local mappings = {}
  local f = fontloader.open(path)
  local metrics = fontloader.to_table(f)
  fontloader.close(f)
  local glyphs = metrics.glyphs
  local map = metrics.map.map
  -- we need to loop over character to glyph mapping
  for i = 0, #map do
    local glyph = map[i]
    if glyph then
      local entry = glyphs[glyph]
      entry.width = entry.width or 0
      mappings[#mappings+1] = string.format("%s,%s,%s,%f,%s", i, glyph, tounicode(i), wdt_fact * tonumber(entry.width), 0)
      -- print(mappings[#mappings], entry.unicode, i)
    end
  end
  update_font_map_raw(entry, path, metrics)
  return mappings, metrics
end

local function process_luaotfload_font(fontname, path, entry)
  -- get the font file name without extension, in lowercase and replace underscores 
  local font_base = string.lower(path:match("([^%/]+)%..-$") or ""):gsub("_", "-")
  -- try to find it in Luaotfload cache
  local cache_path = kpse.expand_var("$TEXMFVAR")  .. "/luatex-cache/generic/fonts/otl/" .. font_base .. ".luc"
  local status = lfs.attributes(cache_path)
  if not status then return nil, "Cannot load font cache file: ".. cache_path end
  local metrics = dofile(cache_path)
  local mappings = {}
  local metadata = metrics.metadata
  -- we need units to calculate correct 
  local units = metadata.units or 1000
  -- 
  local font_size = 10 
  for x, char in table.sortedhash(metrics.descriptions) do
    char.width = char.width or 0
    mappings[#mappings+1] = string.format("%s,%s,%s,%f,%s", x, char.index, tounicode(x), tonumber(char.width) / units * (font_size * 65536 ), 0)
  end
  local metadata = metrics.metadata or {}
  entry.psname = metadata.fontname
  entry.fullname = metadata.fullname
  entry.family = metadata.family
  entry.subfamily = metadata.subfamily
  entry.monospaced = metadata.monospaced
  entry.path = path
  return mappings, metrics
end

local function process_font(fontname, path, entry)
  local mappings, metrics = process_luaotfload_font(fontname, path, entry)
  if type(mappings) ~= "table" then -- we couldn't load font from Luaotfload cache
    return process_raw_font(fontname, path, entry)
  end
  return mappings, metrics
end

local function save_font_map(job_name, font_map)
  -- updated tex4ht needs mapping between DVI font name, font path and other info, like:
  -- "Linux Libertine O"		LinLibertineO	Linux Libertine O	>/usr/.../LinLibertine_R.otf
  local f = io.open(xdvipsk_dir .. "/" .. job_name .. ".opentype.map", "w")
  for _, entry in pairs(font_map) do
    f:write(string.format("%s\t\t%s\t%s\t>%s\t%s\n", entry.dvi_name, entry.psname, entry.fullname, entry.path, entry.subfamily))
  end
  f:close()
end

local function write_mappings(fonts, font_map)
  if not lfs.isdir(xdvipsk_dir) then
    lfs.mkdir(xdvipsk_dir)
  end
  for fontname, path in pairs(fonts) do
    local entry = font_map[path]
    local mappings, metrics =  process_font(fontname, path, entry)
    -- update_font_map(font_map, path, metrics)
    local fullname = entry.fullname -- use version of font name obtained from the font itself
    local f = io.open(xdvipsk_dir .."/" .. fullname .. ".encodings.map", "w") 
    f:write(table.concat(mappings, "\n"))
    f:close()
  end
end

local dvi_file = arg[1] or "sample.dvi"

-- address of the Luaotfload font cache file. 
local cachefile  = kpse.expand_var("$TEXMFVAR")  .. "/luatex-cache/generic/names/luaotfload-names.luc"
local mapping, fontnames = get_mappings(cachefile)
local fonts, font_map = get_fonts(dvi_file, mapping, fontnames)
write_mappings(fonts, font_map)
local job_name = dvi_file:gsub("%..-$", "")
save_font_map(job_name, font_map)

-- -- local libertine = kpse.find_file("LinLibertine_R.otf", "opentype fonts")
local libertine = mapping["amiri"]

local f = fontloader.open(libertine)
local metrics = fontloader.to_table(f)
fontloader.close(f)

for k,v in pairs(metrics.names[1].names) do 
  -- if type(v) == "table" then
    print(k,v) 
  -- end
end

-- local pokus = dofile(kpse.expand_var("$TEXMFVAR") .. "/luatex-cache/generic/fonts/otl/linlibertine-r.luc")
-- -- local pokus = dofile("/home/mint/.texlive2019/texmf-var/luatex-cache/generic/fonts/hb/:home:mint:.fonts:FiraSans-Bold.otf:1")
-- print("---------------")
-- for k,v in pairs(pokus.metadata) do
--   print(k,v)
-- end

-- for _,char in utf8.codes("Příliš žluťoučký kůň") do
--   local glyph = metrics.map.map[char]
--   local unicode = metrics.map.backmap[glyph]
--   print(utf8.char(unicode), char, glyph, unicode)
-- end

-- local icodepoint = utf8.codepoint("í")
-- local icute = metrics.map.map[icodepoint]


-- print(utf8.codepoint("í"), icute,  unicode.latin1.byte("í") )
-- for k, v in pairs(metrics.glyphs[icute]) do
--   -- if type(v) == "table" then
--     print(k, v) 
--   -- end
-- end

-- for k,v in pairs(unicode["utf8"]) do print(k,v) end
