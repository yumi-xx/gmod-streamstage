AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "cl_thirdperson.lua" )
AddCSLuaFile( "shared.lua" )

include( "shared.lua" )

hook.Add("PlayerInitialSpawn", "FullLoadSetup", function(ply)
	hook.Add("SetupMove", ply, function(self, ply, _, cmd)
		if self == ply and not cmd:IsForced() then
			hook.Run("PlayerFullLoad", self)
			hook.Remove("SetupMove", self)
		end
	end )
end )

hook.Add("PlayerFullLoad", "FullLoad", function(p)
	-- "Team" assignments
	if p:SteamID() == "STEAM_0:1:53590647" then
		-- Hey, that's me!
		p:SetTeam(GAMEMODE.TeamCreator)
	elseif p:IsUserGroup("DJ") then
		p:SetTeam(GAMEMODE.TeamDJCrew)
	elseif p:IsAdmin() or p:IsSuperAdmin() then
		p:SetTeam(GAMEMODE.TeamAdmin)
	else
		p:SetTeam(GAMEMODE.TeamAudience)
	end

	-- Broadcast chat
	GAMEMODE:TellAll("Everyone welcome "..p:Name().."!")

	-- Update parameters
	GAMEMODE:TellParameters(p)
	-- Hook into stream if we're in the middle of it
	if GAMEMODE.NowPlaying then
		net.Start("streamstage-start")
		net.Send(p)
	end
end )

function GM:BroadcastStart()
	self.NowPlaying = true

	for _, v in pairs(player.GetAll()) do
		net.Start("streamstage-start")
		net.Send(v)
	end
end

function GM:BroadcastStop()
	self.NowPlaying = false

	for _, v in pairs(player.GetAll()) do
		net.Start("streamstage-stop")
		net.Send(v)
	end
end

function GM:BroadcastParameters()
	for _, v in pairs(player.GetAll()) do
		self:TellParameters(v)
	end
end

function GM:TellParameters(p)
	net.Start("streamstage-parameters")
	net.WriteUInt(GAMEMODE.Attenuation, GAMEMODE.NetUIntSize)
	if not GAMEMODE.Emitter then
		-- Play at origin if there is no DJ board spawned
		net.WriteUInt(p:GetViewEntity():EntIndex(), GAMEMODE.NetUIntSize)
	else
		net.WriteUInt(GAMEMODE.Emitter:EntIndex(), GAMEMODE.NetUIntSize)
	end
	net.WriteString(GAMEMODE.SoundURL)
	net.WriteInt(GAMEMODE.Volume, GAMEMODE.NetUIntSize)
	net.WriteBool(GAMEMODE.NowPlaying)
	net.Send(p)
end

function GM:TellAll(msg)
	for _, p in pairs(player.GetAll()) do
		p:ChatPrint(msg)
	end
end

function GM:PlayerSetModel(p)
	-- Override buggy thirdperson model
	if p:GetModel() == "models/player.mdl" then
	-- https://www.youtube.com/watch?v=1_hnTNlYCbw
		p:SetModel("models/player/phoenix.mdl")
	end
end
