kpse.set_program_name "luatex"

local xdvipsk_dir = ".xdvipsk"

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
    mapping[x.plainname] = x.fullpath
    -- remove file extension
    local fontname = x.basename:gsub("%..-$", "")
    fontnames[fontname] = x.plainname
  end
  return mapping, fontnames
end

local function get_fonts(dvi_file, mapping, fontnames)
  -- find fonts used in the DVI file
  local used_fonts = {}
  local dviasm = io.popen("dviasm ".. dvi_file)
  local fntdef_found = false -- we don't want to parse the full DVI file
  for line in dviasm:lines() do
    -- opentype fonts are in quotes
    local font = line:match("fntdef: (.+) at")
    if font then
      fntdef_found = true
      if font:match("^\"") then
        -- plainname is used
        font = font:match('"(.-)"')
      elseif font:match("^%[") then
        -- basename is used
        font = font:match("%[(.-)%]")
        font = fontnames[font] or false
      end
      if mapping[font] then
        used_fonts[font] = mapping[font]
      end
    elseif fntdef_found then
      -- break the processing after we had read all fntdefs
      break
    end
  end
  return used_fonts
end


local function process_font(fontname, path)
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
      mappings[#mappings+1] = string.format("%s,%s,%s,%s,%s", i, glyph, tounicode(i), entry.width, 0)
      print(mappings[#mappings], entry.unicode, i)
    end
  end
  return mappings
end

local function write_mappings(fonts)
  if not lfs.isdir(xdvipsk_dir) then
    lfs.mkdir(xdvipsk_dir)
  end
  for fontname, path in pairs(fonts) do
    local mappings =  process_font(fontname, path)
    
    local f = io.open(xdvipsk_dir .."/" .. fontname .. ".encodings.map", "w")
    f:write(table.concat(mappings, "\n"))
    f:close()
  end
end

local dvi_file = arg[1] or "sample.dvi"

-- address of the Luaotfload font cache file. 
local cachefile  = kpse.expand_var("$TEXMFVAR")  .. "/luatex-cache/generic/names/luaotfload-names.luc"
local mapping, fontnames = get_mappings(cachefile)
local fonts = get_fonts(dvi_file, mapping, fontnames)
write_mappings(fonts)

-- -- local libertine = kpse.find_file("LinLibertine_R.otf", "opentype fonts")
-- local libertine = mapping["Linux Libertine O"]

-- local f = fontloader.open(libertine)
-- local metrics = fontloader.to_table(f)
-- fontloader.close(f)

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
