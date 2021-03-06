#!./koreader-base
--[[
    KindlePDFViewer: a reader implementation
    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--
require "pdfreader"
require "djvureader"
require "koptreader"
require "picviewer"
require "crereader"
require "filechooser"
require "settings"
require "screen"
require "commands"
require "dialog"
require "readerchooser"
require "defaults"
require "gettext"

function openFile(filename)
	local reader = ReaderChooser:getReaderByName(filename)
	if reader then
		InfoMessage:inform(_("Opening document... "), DINFO_NODELAY, 0, MSG_AUX)
		reader:preLoadSettings(filename)
		local ok, err = reader:open(filename)
		if ok then
			reader:loadSettings(filename)
			page_num = reader:getLastPageOrPos()
			if type(page_num) == "string" then
				reader:goto(page_num, true, "xpointer")
			else
				reader:goto(page_num, true)
			end
			G_reader_settings:saveSetting("lastfile", filename)
			return reader:inputLoop()
		else
			if err then
				Debug("openFile(): "..err)
				InfoMessage:inform(err:sub(1,30), DINFO_DELAY, 1, MSG_ERROR)
			else
				InfoMessage:inform(_("Error opening document "), DINFO_DELAY, 1, MSG_ERROR)
			end
		end
	end
	return true -- on failed attempts, we signal to keep running
end

function showusage()
	print(_("usage: ./reader.lua [OPTION] ... path"))
	print(_("Read PDF/DjVu/ePub/MOBI/FB2/CHM/HTML/TXT/DOC/RTF/JPEG on your E-Ink reader"))
	print("")
	print(_("-d, --debug               start in debug mode"))
	print(_("                          (floating point notation, e.g. \"1.5\")"))
	print(_("-h, --help                show this usage help"))
	print("")
	print(_("If you give the name of a directory instead of a file path, a file"))
	print(_("chooser will show up and let you select a PDF|DJVU file"))
	print("")
	print(_("If you don't pass any path, the last viewed document will be opened"))
	print("")
	print(_("This software is licensed under the GPLv3."))
	print(_("See http://github.com/koreader/kindlepdfviewer for more info."))
	return
end

if ARGV[1] == "-h" then
	return showusage()
end

local argidx = 1
if ARGV[1] == "-d" then
	argidx = argidx + 1
else
	Debug = function() end
	dump = function() end
	debug = function() end
end

local vfile = io.open("git-rev", "r")
if vfile then
	G_program_version = vfile:read("*a") or "?"
	G_program_version = G_program_version:gsub("[\n\r]+", "")
	vfile.close()
else
	G_program_version = _("(unknown version)")
end

if util.isEmulated()==1 then
	os.remove("emu_event")
	os.execute("mkfifo emu_event")
	input.open("emu_event")
	-- SDL key codes
	setEmuKeycodes()
else
	input.open("fake_events")
	input.open("/dev/input/event0")
	input.open("/dev/input/event1")

	-- check if we are running on Kindle 3 (additional volume input)
	if FileExists("/dev/input/event2") then
		Debug("Auto-detected Kindle 3")
		input.open("/dev/input/event2")
		setK3Keycodes()
	end
end

G_screen_saver_mode = false
G_charging_mode = false
fb = einkfb.open("/dev/fb0")
-- read current rotation mode
Screen:updateRotationMode()
Screen.native_rotation_mode = Screen.cur_rotation_mode

-- force portrait mode
Screen:setRotationMode(0)

-- set up reader's setting: font
G_reader_settings = DocSettings:open(".reader")
fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
	-- we need to iterate over all fonts used in reader to support upgrade from older configuration
	for name,path in pairs(fontmap) do
		if Font.fontmap[name] then
			Font.fontmap[name] = path
		else
			Debug("missing "..name.." in user configuration, using default font "..path)
		end
	end
end

-- set up the mode to manage files
FileChooser.filemanager_mode = G_reader_settings:readSetting("filemanager_mode") or FileChooser.RESTRICTED
InfoMessage:initInfoMessageSettings()
local tmp = G_reader_settings:readSetting("G_battery_logging")
if tmp ~= nil then
	G_battery_logging = tmp
else
	G_battery_logging = DBATTERY_LOGGING
end

-- initialize global settings shared among all readers
UniReader:initGlobalSettings(G_reader_settings)
PDFReader:init()
DJVUReader:init()
KOPTReader:init()
PICViewer:init()
CREReader:init()

-- display directory or open file
local patharg = G_reader_settings:readSetting("lastfile")
if ARGV[argidx] and lfs.attributes(ARGV[argidx], "mode") == "directory" then
	FileChooser:setPath(ARGV[argidx])
	FileChooser:choose()
elseif ARGV[argidx] and lfs.attributes(ARGV[argidx], "mode") == "file" then
	openFile(ARGV[argidx])
elseif patharg and lfs.attributes(patharg, "mode") == "file" then
	openFile(patharg)
else
	return showusage()
end

-- save reader settings
G_reader_settings:saveSetting("fontmap", Font.fontmap)
InfoMessage:saveInfoMessageSettings()
G_reader_settings:close()

-- @TODO dirty workaround, find a way to force native system poll
-- screen orientation and upside down mode 09.03 2012
fb:setOrientation(Screen.native_rotation_mode)

input.closeAll()
if util.isEmulated()==0 then
	os.execute("killall -cont cvm")
	os.execute('echo "send '..KEY_MENU..'" > /proc/keypad;echo "send '..KEY_MENU..'" > /proc/keypad')
end
