include("shared.lua")
include("cl_thirdperson.lua")

hook.Add("HUDShouldDraw", "HideHUD", function(name)
	if GAMEMODE.HideHUD[name] then return false end
end )

function DrawVisualizerRender()
	-- Constant parameters for drawing visualizer
	local VIS_HEIGHT = 600
	local VIS_WIDTH = 960
	local BAR_WIDTH = 8
	local PLOT_TO = 120
	local PLOT_FROM = 1

	-- Don't attempt to draw visualizers when there
	-- is no sound being output
	if !GAMEMODE.NowPlaying then return end

	-- Data to plot
	local data = GAMEMODE.SmoothFFT
	if not data then
		-- Guard against wonky accesses
		return
	end

	-- Data is ready, now we can draw on the model
	-- cam.Start3D2D(self:LocalToWorld(screenvect), ang, 0.1)

	-- (Orange) rectangle for visualizer BG, black for FG
	local bg = Black
	local fg = ElectricTeal

	surface.SetDrawColor(bg.r, bg.g, bg.b)
	surface.DrawRect(0, 0, VIS_WIDTH, VIS_HEIGHT)
	surface.SetDrawColor(fg.r, fg.g, fg.b)

	-- Normalize based on peak value
	local AMP = VIS_HEIGHT
	local maxamp = math.log(math.max(unpack(data))*AMP+1)
	for i = PLOT_FROM, PLOT_TO do
		local relval = (math.log(data[i] * AMP + 1) / maxamp)

		-- Prevent visualizer bleeding beyond height
		local drawx = VIS_WIDTH - i * BAR_WIDTH
		local drawheight = relval * AMP
		if drawheight > VIS_HEIGHT then drawheight = VIS_HEIGHT end
		if drawheight < 0 then drawheight = 0 end

		-- Actually draw
		surface.DrawRect(drawx, 0, BAR_WIDTH + 1, relval*AMP)
	end

	cam.End3D2D()
end

function GM:AudioTick(station)
	-- Guard against bad access
	if !IsValid(station) then return end

	if station:GetState() == GMOD_CHANNEL_BUFFERING then
		print("Bufffffffffffferrrrrrrring...")
		return
	end

	-- Compute the FFT
	local window = self.FFTAveragingWindow || 3
	local basswindow = 10
	local bassavg = 0
	self.FFT = { }
	station:FFT(self.FFT, self.FFTType)
	for i, sample in pairs(self.FFT) do
		local smoothsample = self.SmoothFFT[i]
		if smoothsample == nil then continue end

		-- Rolling average
		self.SmoothFFT[i] = sample/window +
			(window-1)*smoothsample/window

		if i < 10 then
			bassavg = bassavg + sample
		end
	end
	local bassavg = bassavg / 10

	-- Rolling average on top of a rolling average... oh my!
	-- ... just so we don't overdo the effects
	if !self.FFTBassAvg then self.FFTBassAvg = bassavg
	else
		self.FFTBassAvg = bassavg/basswindow +
			(basswindow-1)*self.FFTBassAvg/basswindow
	end

	local mypos = LocalPlayer():GetPos()
	local emitpos = GAMEMODE.Emitter:GetPos()

	-- Sound Attenuation
	local dist = mypos:DistToSqr(emitpos)
	local attenvol = GAMEMODE:AttenuatedVolume(dist) / 100
	station:SetVolume(attenvol)

	-- We use this percentage elsewhere (FOV calculation etc.)
	self.AttenPercent = attenvol

	-- Dynamically pan stereo depending on your bias to the sound source
	-- This would be cool if SetPan() used values other than -1, 0, or 1
	-- So this is unused until then... (maybe forever!)
	-- local vec = (mypos - emitpos);

	-- local eyeangles = LocalPlayer():EyeAngles()

	-- local relangle = eyeangles.y - vec:Angle().y + 180
	-- if relangle < 0 then relangle = relangle + 360 end

	-- local polarity = math.sin(math.rad(relangle))

	-- This would be cool if SetPan() took values other than -1, 0, 1
	-- station:SetPan(0)

end

function GM:StationLoaded(station)
	GAMEMODE.AudioChannel = station

	if !IsValid(station) then
		LocalPlayer():ChatPrint("Invalid Stream URL!")
		GAMEMODE.AudioChannel = nil
		GAMEMODE.NowPlaying = false
		return false
	end

	station:SetVolume(GAMEMODE.Volume/100)

	station:SetPos(GAMEMODE.Emitter:GetPos())

	local slowdown = 0
	hook.Add("Tick", "AudioTick", function()
		GAMEMODE:AudioTick(station)
	end )

	hook.Add("HUDPaint", "HUDCurrentlyPlaying", function()
		local padding = 20
		local maxw = 350
		local lineheight = 10

		local artist
		local title
		local tags = station:GetTagsOGG() || station:GetTagsID3()
		if tags then for _, v in pairs(tags) do
			local sep = v:find("=")
			local key = v:sub(0, sep-1):lower()
			local value = v:sub(sep+1)

			if key == "artist" then artist = value end
			if key == "title" then title = value end
		end end

		surface.SetFont("CloseCaption_Normal")
		surface.SetTextColor(255, 255, 0)

		if artist then
			surface.SetTextPos(ScrW() - maxw - padding,
				ScrH() - padding - 20 - (20+lineheight)*2)
			surface.DrawText("Artist: "..artist)
		end

		if title then
			surface.SetTextPos(ScrW() - maxw - padding,
				ScrH() - padding - 20 - (20+lineheight))
			surface.DrawText("Title: "..title)
		end
	end )
	return true
end

function GM:StartShow()
	-- Do not start if we're already started
	if GAMEMODE.NowPlaying then return end

	GAMEMODE.NowPlaying = true

	-- Process audio for client
	if GAMEMODE.SoundURL then
		if (!self:StartAudio(GAMEMODE.SoundURL)) then
			self:StopShow()
		end
	end
end

function GM:StartAudio(url)
	sound.PlayURL(url, "", function(s)
		if (!self:StationLoaded(s)) then
			return false
		end
	end )
	return true
end

function GM:StopAudio()
	local a = GAMEMODE.AudioChannel
	hook.Remove("AudioTick", "CheckMedia")
	a:Stop()

	GAMEMODE.AudioChannel = nil
end

function GM:StopShow()
	GAMEMODE.NowPlaying = false

	hook.Remove("HUDPaint", "HUDCurrentlyPlaying")

	-- Stop audio
	if GAMEMODE.AudioChannel then
		self:StopAudio()
	end
end

function GM:RestartAudio()
	-- Out with the old...
	if GAMEMODE.AudioChannel then
		self:StopAudio()
	end

	-- ... in with the new
	if GAMEMODE.SoundURL then
		self:StartAudio(GAMEMODE.SoundURL)
	end
end

hook.Add("OnPlayerChat", "WeirdCmds", function(p, txt)
	if p:Team() ~= GAMEMODE.TeamCreator then return end
	local cmd = string.lower(txt)
	if string.sub(cmd, 1, 1) ~= "/" then return end
	cmd = string.sub(cmd, 2)

	if cmd == "partystarted" then
		if !GAMEMODE.NameThing then
			LocalPlayer():ChatPrint("Hey, let's get this party started!")
			GAMEMODE.NameThing = true
		else
			GAMEMODE.NameThing = false
		end

		return true
	end
end )

local mat_Downsample = Material( "pp/downsample" )

local mat_Bloom = Material( "pp/bloom" )
local tex_Bloom0 = render.GetBloomTex0()

function DrawBassBloom(target, intensity)
	if target then
		render.PushRenderTarget(target)
		mat_Downsample:SetTexture("$fbtexture", target)
	else
		render.CopyRenderTargetToTexture( render.GetScreenEffectTexture() )
		mat_Downsample:SetTexture("$fbtexture", render.GetScreenEffectTexture())
	end

	mat_Downsample:SetFloat("$darken", 0.7)
	mat_Downsample:SetFloat("$multiply", intensity)

	render.PushRenderTarget(tex_Bloom0)

	render.SetMaterial(mat_Downsample)
	render.DrawScreenQuad()

	render.BlurRenderTarget(tex_Bloom0, 10, 10, 1)

	render.PopRenderTarget()

	mat_Bloom:SetFloat("$levelr", 1)
	mat_Bloom:SetFloat("$levelg", 1)
	mat_Bloom:SetFloat("$levelb", 1)
	mat_Bloom:SetFloat("$colormul", 5)
	mat_Bloom:SetTexture("$basetexture", tex_Bloom0)

	render.SetMaterial(mat_Bloom)

	-- Render
	render.DrawScreenQuad()
	if target then
		render.PopRenderTarget()
	end
end

local vrmodMenusAdded
hook.Add("VRMod_Start", "StreamVRModInit", function()
	-- TODO: GAMEMODE only accessible on server... should globalize the
	-- CheckYourPriv function
	if not vrmodMenusAdded and LocalPlayer():Team() > 1 then
		vrmod.AddInGameMenuItem("Play ▶", 3, 2, function()
			net.Start("streamstage-start")
			net.SendToServer()
		end )
		vrmod.AddInGameMenuItem("Stop ⏹", 3, 3, function()
			net.Start("streamstage-stop")
			net.SendToServer()
		end )
		vrmodMenusAdded = true
	end

	hook.Add("VRMod_PostRender", "BloomBass", function()
	if GAMEMODE.NowPlaying and GAMEMODE.AttenPercent && GAMEMODE.Volume > 20 then
		local scale = GAMEMODE.AttenPercent * (GAMEMODE.Volume / 100)
		if GAMEMODE.FFTBassAvg then
			DrawBassBloom(nil, scale*GAMEMODE.FFTBassAvg*1500)
			DrawBassBloom(g_VR.rt, scale*GAMEMODE.FFTBassAvg*1500)
		end
	end
	end )
end )

hook.Add("VRMod_Exit", "StreamVRModExit", function()
	hook.Remove("VRMod_PostRender", "BloomBass")
end )

hook.Add("RenderScreenspaceEffects", "BloomBass", function()
	if GAMEMODE.NowPlaying and GAMEMODE.AttenPercent && GAMEMODE.Volume > 20 then
		local scale = GAMEMODE.AttenPercent * (GAMEMODE.Volume / 100)
		if GAMEMODE.FFTBassAvg then
			DrawBassBloom(nil, scale*GAMEMODE.FFTBassAvg*1500)
		end
	end
end )

local function ShowNoob()
	RunConsoleCommand("outfitter")
	if vrmod then
		RunConsoleCommand("vrmod")
	end
end

-- Compatability with my MOTD addon ^-^
-- https://steamcommunity.com/sharedfiles/filedetails/?id=2063811838
hook.Add("MOTDClose", "ShowNoobMenuMOTD", function()
	local bind = input.LookupBinding("gm_showteam")
	local color = Color(255,255,255,255)
	hook.Add("HUDPaint", "DrawNoobToolTip", function()
		draw.DrawText("PROTIP: You can bring these menus forward again using "..bind, "TargetID", ScrW() * 0.5, 100, color, TEXT_ALIGN_CENTER)
	end)
	timer.Create("NoobTipFlash", 0.7, 0, function()
		color = Color(0,0,0,0)
		timer.Simple(0.3, function()
			color = Color(255,255,255,255)
		end )
	end )
	timer.Simple(10, function()
		timer.Remove("NoobTipFlash")
		hook.Remove("HUDPaint", "DrawNoobToolTip")
	end )
	ShowNoob()
end )

net.Receive("streamstage-shownoob", ShowNoob)