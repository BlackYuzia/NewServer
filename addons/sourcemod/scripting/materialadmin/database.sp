void MAConnectDB()
{
	char sError[256];
	g_dSQLite = SQLite_UseDatabase("maDatabase", sError, sizeof(sError));
	if (!g_dSQLite)
		SetFailState("%sLocal Database failure (%s)", MAPREFIX, sError);
	else
		CreateTables();

	ConnectBd(BDCONNECT_ADMIN, 0);
	
	InsertServerInfo();
}

void ConnectBd(int iType, int iClient)
{
	if (g_dDatabase)
	{
		delete g_dDatabase;
		g_dDatabase = null;
	#if MADEBUG
		LogToFile(g_sLogDateBase, "ConnectBd: lost");
	#endif
	}

	if (SQL_CheckConfig("materialadmin"))
	{
		DataPack dPack = new DataPack();
		dPack.WriteCell((!iClient)?0:GetClientUserId(iClient));
		dPack.WriteCell(iType);
		Database.Connect(SQL_Callback_ConnectBd, "materialadmin", dPack);
	}
	else
	{
		LogToFile(g_sLogDateBase, "Database failure: Could not find Database conf \"materialadmin\"");
		g_dDatabase = null;
		FireOnConnectDatabase(g_dDatabase);
		SetFailState("%sDatabase failure: Could not find Database conf \"materialadmin\"", MAPREFIX);
	}
}

public void SQL_Callback_ConnectBd(Database db, const char[] sError, any data)
{
	if (sError[0])
		LogToFile(g_sLogDateBase, "ConnectBd Query Failed: %s", sError);
	
	g_dDatabase = db;
	
	FireOnConnectDatabase(g_dDatabase);
	
	DataPack dPack = view_as<DataPack>(data);
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	int iType = dPack.ReadCell();

	if (g_dDatabase)
	{
		SQL_LockDatabase(g_dDatabase);
		SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
		SQL_UnlockDatabase(g_dDatabase);
		//g_dDatabase.SetCharset("utf8");
		switch(iType)
		{
			case BDCONNECT_ADMIN: 	AdminHash();
			case BDCONNECT_COM:		ReplyToCommand(iClient, "%sYes connect bd", MAPREFIX);
			case BDCONNECT_MENU:
			{
				if (iClient)
					PrintToChat2(iClient, "%T",  "Reload connect ok", iClient);
			}
		}
		KillTimerBekap();
	#if MADEBUG
		LogToFile(g_sLogDateBase, "ConnectBd: yes");
	#endif
	}
	else
	{
		switch(iType)
		{
			case BDCONNECT_COM:		ReplyToCommand(iClient, "%sNo connect bd", MAPREFIX);
			case BDCONNECT_MENU:
			{
				if (iClient)
					PrintToChat2(iClient, "%T",  "Reload connect no", iClient);
			}
		}
	#if MADEBUG
		LogToFile(g_sLogDateBase, "ConnectBd: no");
	#endif
	}
}

void CreateTables()
{
	SQL_LockDatabase(g_dSQLite);
	SQL_FastQuery(g_dSQLite, "PRAGMA encoding = \"UTF-8\"");
	if(SQL_FastQuery(g_dSQLite, "\
			CREATE TABLE IF NOT EXISTS `offline` (\
			`id` INTEGER PRIMARY KEY AUTOINCREMENT,\
			`auth` VARCHAR(32) UNIQUE ON CONFLICT REPLACE,\
			`ip` VARCHAR(24) NOT NULL,\
			`name` VARCHAR(64) DEFAULT 'unknown',\
			`disc_time` NUMERIC NOT NULL);\
		") == false)
	{
		char sError[256];
		SQL_GetError(g_dSQLite, sError, sizeof(sError));
		SetFailState("%s Query CREATE TABLE failed! %s", MAPREFIX, sError);
	}
	if(SQL_FastQuery(g_dSQLite, "\
			CREATE TABLE IF NOT EXISTS `bekap` (\
			`id` INTEGER PRIMARY KEY AUTOINCREMENT,\
			`query` text NOT NULL,\
			`time` NUMERIC NOT NULL);\
		") == false)
	{
		char sError[256];
		SQL_GetError(g_dSQLite, sError, sizeof(sError));
		SetFailState("%s Query CREATE TABLE failed! %s", MAPREFIX, sError);
	}
	SQL_UnlockDatabase(g_dSQLite);
}
//------------------------------------------------------------------------------------------------------------
bool ChekBD(Database db, char[] sBuffer)
{
	if (!db)
	{
		LogToFile(g_sLogDateBase, "No connect Database: %s", sBuffer);
		return false;
	}
	return true;
}
//------------------------------------------------------------------------------------------------------------
void ClearBekap()
{
	char sQuery[64];
	FormatEx(sQuery, sizeof(sQuery), "DROP TABLE  `bekap`");
	g_dSQLite.Query(SQL_Callback_DeleteBekaps, sQuery, _, DBPrio_High);
}

public void SQL_Callback_DeleteBekaps(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_DeleteBekaps: %s", sError);
	else
		CreateTables();
}
//------------------------------------------------------------------------------------------------------------
// offline
void ClearHistories()
{
	char sQuery[64];
	FormatEx(sQuery, sizeof(sQuery), "DROP TABLE  `offline`");
	g_dSQLite.Query(SQL_Callback_DeleteClients, sQuery, _, DBPrio_High);
}

public void SQL_Callback_DeleteClients(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_DeleteClients Query Failed: %s", sError);
	else
		CreateTables();
}

void SetOflineInfo(char[] sSteamID, char[] sName, char[] sIP)
{
	char sEName[MAX_NAME_LENGTH*2+1],
		sQuery[512];

	g_dSQLite.Escape(sName, sEName, sizeof(sEName));

	FormatEx(sQuery, sizeof(sQuery), "\
			INSERT INTO `offline` (`auth`, `ip`, `name`, `disc_time`) \
			VALUES ('%s', '%s', '%s', %i)", 
		sSteamID, sIP, sEName, GetTime());

	g_dSQLite.Query(SQL_Callback_AddClient, sQuery, _, DBPrio_High);
#if MADEBUG
	LogToFile(g_sLogDateBase, "SetOflineInfo:QUERY: %s", sQuery);
#endif
}

public void SQL_Callback_AddClient(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_AddClient Query Failed: %s", sError);
}

void DelOflineInfo(char[] sSteamID)
{
	char sQuery[256];

	FormatEx(sQuery, sizeof(sQuery), "\
			DELETE FROM `offline` WHERE `auth` = '%s'", 
		sSteamID);

	g_dSQLite.Query(SQL_Callback_DeleteClient, sQuery, _, DBPrio_High);
#if MADEBUG
	LogToFile(g_sLogDateBase, "DelOflineInfo:QUERY: %s", sQuery);
#endif
}

public void SQL_Callback_DeleteClient(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_DeleteClient Query Failed: %s", sError);
}

//меню выбора игрока офлайн
void BdTargetOffline(int iClient)
{
	char sQuery[324];

	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT `id`, `auth`, `name`, `disc_time` \
			FROM `offline` ORDER BY `id` DESC LIMIT %d;", 
		g_iOffMaxPlayers);

	g_dSQLite.Query(ShowTargetOffline, sQuery, iClient, DBPrio_High);
}

void BdGetInfoOffline(int iClient, int iId)
{
	char sQuery[224];

	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT `auth`, `ip`, `name` FROM `offline` \
			WHERE `id` = '%i' LIMIT 1", 
		iId);

	g_dSQLite.Query(SQL_Callback_GetInfoOffline, sQuery, iClient, DBPrio_High);
#if MADEBUG
	LogToFile(g_sLogDateBase, "GetInfoOffline:QUERY: %s", sQuery);
#endif
}

public void SQL_Callback_GetInfoOffline(Database db, DBResultSet dbRs, const char[] sError, any iClient)
{
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "SQL_Callback_GetInfoOffline Query Failed: %s", sError);
		PrintToChat2(iClient, "%T", "Failed to player", iClient);
	}

	if (dbRs.FetchRow())
	{
		dbRs.FetchString(0, g_sTarget[iClient][TSTEAMID], sizeof(g_sTarget[][]));
		dbRs.FetchString(1, g_sTarget[iClient][TIP], sizeof(g_sTarget[][]));
		dbRs.FetchString(2, g_sTarget[iClient][TNAME], sizeof(g_sTarget[][]));
		ShowTypeMenu(iClient);
	}
	else
		PrintToChat2(iClient, "%T", "Failed to player", iClient);
}
//------------------------------------------------------------------------------------------
void BdGetMuteType(int iClient, int iTarget)
{
	if (ChekBD(g_dDatabase, "GetMuteType"))
	{
		DataPack dPack = new DataPack();
		dPack.WriteCell(iClient);
		dPack.WriteCell(iTarget);
		
		if (iTarget)
			GetClientAuthId(iTarget, TYPE_STEAM, g_sTarget[iClient][TSTEAMID], sizeof(g_sTarget[][]));
		
		char sQuery[524];
		FormatEx(sQuery, sizeof(sQuery), "\
					SELECT  c.`type`, a.`authid` \
					FROM `%s_comms` AS c \
					LEFT JOIN `%s_admins` AS a ON a.`aid` = c.`aid` \
					LEFT JOIN `%s_srvgroups` AS g ON g.`name` = a.`srv_group` \
					WHERE `RemoveType` IS NULL  AND c.`authid` REGEXP '^STEAM_[0-9]:%s$' \
					AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) LIMIT 1", 
			g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, g_sTarget[iClient][TSTEAMID][8]);

		g_dDatabase.Query(SQL_Callback_GetMuteType, sQuery, dPack, DBPrio_High);
	#if MADEBUG
		LogToFile(g_sLogDateBase, "GetMuteType:QUERY: %s", sQuery);
	#endif
	}
	else
		ShowTypeMuteMenu(iClient);
}

public void SQL_Callback_GetMuteType(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	DataPack dPack = view_as<DataPack>(data);
	dPack.Reset();
	int iClient = dPack.ReadCell();
	int iTarget = dPack.ReadCell();

	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "SQL_Callback_GetMuteType Query Failed: %s", sError);
		//g_iTargetMuteType[iTarget] = 0;
		ShowTypeMuteMenu(iClient);
		return;
	}

	if (dbRs.FetchRow())
	{
		g_iTargetMuteType[iTarget] = dbRs.FetchInt(0);
		dbRs.FetchString(1, g_sTargetMuteSteamAdmin[iTarget], sizeof(g_sTargetMuteSteamAdmin[]));
	}
	else
		g_iTargetMuteType[iTarget] = 0;

#if MADEBUG
	if(iTarget && IsClientInGame(iTarget))
		LogToFile(g_sLogDateBase, "GetMuteType:%N: %d", iTarget, g_iTargetMuteType[iTarget]);
	else
		LogToFile(g_sLogDateBase, "GetMuteType:%d: %d", iTarget, g_iTargetMuteType[iTarget]);
#endif

	ShowTypeMuteMenu(iClient);
}
// поиск инфы о муте в меню
void BDGetInfoMute(int iClient, char[] sOption)
{
	if (ChekBD(g_dDatabase, "GetInfoMute"))
	{
		char sSteamID[MAX_STEAMID_LENGTH];
		int iTarget = GetClientOfUserId(StringToInt(sOption));
		if (iTarget)
			GetClientAuthId(iTarget, TYPE_STEAM, sSteamID, sizeof(sSteamID));
		
		char sQuery[524];
		FormatEx(sQuery, sizeof(sQuery), "\
					SELECT  c.`created`, c.`ends`, c.`length`, c.`reason`, a.`user` \
					FROM `%s_comms` AS c \
					LEFT JOIN `%s_admins` AS a ON a.`aid` = c.`aid` \
					LEFT JOIN `%s_srvgroups` AS g ON g.`name` = a.`srv_group` \
					WHERE c.`authid` REGEXP '^STEAM_[0-9]:%s$' \
					AND ((`RemoveType` IS NULL AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP())) OR `length` = -1) ORDER BY `bid` DESC LIMIT 1", 
			g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, sSteamID[8]);

		g_dDatabase.Query(SQL_Callback_GetInfoMute, sQuery, iClient, DBPrio_High);
	#if MADEBUG
		LogToFile(g_sLogDateBase, "GetInfoMute:QUERY: %s", sQuery);
	#endif
	}
	else
		PrintToChat2(iClient, "%T", "Reload connect no", iClient);
}

public void SQL_Callback_GetInfoMute(Database db, DBResultSet dbRs, const char[] sError, any iClient)
{

	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "SQL_Callback_GetInfoMute Query Failed: %s", sError);
		PrintToChat2(iClient, "%T", "Reload connect no", iClient);
		return;
	}
	
	int iCreated,
		iEnds,
		iLength;
		
	char sReason[126],
		sNameAdmin[MAX_NAME_LENGTH];

	if (dbRs.FetchRow())
	{
		iCreated = dbRs.FetchInt(0);
		iEnds = dbRs.FetchInt(1);
		iLength = dbRs.FetchInt(2);
		dbRs.FetchString(3, sReason, sizeof(sReason));
		dbRs.FetchString(4, sNameAdmin, sizeof(sNameAdmin));
	}
	else
	{
		PrintToChat2(iClient, "%T", "Failed to player", iClient);
		return;
	}

#if MADEBUG
	LogToFile(g_sLogDateBase, "GetInfoMute:%d, %d, %d, %s, %s", iCreated, iEnds, iLength, sReason, sNameAdmin);
#endif

	ShowInfoMuteMenu(iClient, iCreated, iEnds, iLength, sReason, sNameAdmin);
}
//-----------------------------------------------------------------------------------------------------------------------------
void CheckBanInBd(int iClient, int iTarget, int iType, char[] sSteamIp)
{
	if (ChekBD(g_dDatabase, "CheckBanInBd"))
	{
		char sQuery[560],
			sWhele[256];
		if (sSteamIp[0] == 'S')
			FormatEx(sWhele, sizeof(sWhele), "`type` = 0 AND c.`authid` REGEXP '^STEAM_[0-9]:%s$'", sSteamIp[8]);
		else
			FormatEx(sWhele, sizeof(sWhele), "`type` = 1 AND c.`ip` = '%s'", sSteamIp);
		
		FormatEx(sQuery, sizeof(sQuery), "\
				SELECT  c.`bid`, a.`authid` \
				FROM `%s_bans` AS c \
				LEFT JOIN `%s_admins` AS a ON a.`aid` = c.`aid` \
				LEFT JOIN `%s_srvgroups` AS g ON g.`name` = a.`srv_group` \
				WHERE `RemoveType` IS NULL  AND (%s) \
				AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP())", 
			g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, sWhele);

		DataPack dPack = new DataPack();
		dPack.WriteCell((!iClient)?0:GetClientUserId(iClient));
		dPack.WriteCell(iTarget);
		dPack.WriteCell(iType);
		dPack.WriteString(sSteamIp);
	#if MADEBUG
		LogToFile(g_sLogDateBase, "Checking ban in bd: %s. QUERY: %s", sSteamIp, sQuery);
	#endif
		g_dDatabase.Query(SQL_Callback_CheckBanInBd , sQuery, dPack, DBPrio_High);
	}
	else
		CreateDB(iClient, iTarget, sSteamIp);
}

public void SQL_Callback_CheckBanInBd(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	DataPack dPack = view_as<DataPack>(data);
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	int iTarget = dPack.ReadCell();
	int iType = dPack.ReadCell();
	char sSteamIp[56];
	dPack.ReadString(sSteamIp, sizeof(sSteamIp));
	delete dPack;
	
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "SQL_Callback_CheckBanInBd Query Failed: %s", sError);
		CreateDB(iClient, iTarget, sSteamIp);
		return;
	}
	
	switch(iType)
	{
		case 0:
		{
			if (!dbRs.RowCount)
			{
				if (iClient && IsClientInGame(iClient))
					PrintToChat2(iClient, "%T", "No active bans", iClient, sSteamIp);
				else
					ReplyToCommand(iClient, "%s No active bans found for that filter %s", MAPREFIX, sSteamIp);
			}
			else
			{
				if (dbRs.FetchRow())
				{
					char sSteamID[MAX_STEAMID_LENGTH];

					dbRs.FetchString(1, sSteamID, sizeof(sSteamID));
					
					if (IsUnMuteUnBan(iClient, sSteamID))
						CreateDB(iClient, iTarget, sSteamIp);
					else
					{
						if (iClient && IsClientInGame(iClient))
							PrintToChat2(iClient, "%T", "No access un ban", iClient, sSteamIp);
					}
				}
			}
		}
		case 1:
		{
			if (dbRs.RowCount)
			{
				if (iClient && IsClientInGame(iClient))
					PrintToChat2(iClient, "%T", "Is already banned", iClient, sSteamIp);
				else
					ReplyToCommand(iClient, "%s %s is already banned", MAPREFIX, sSteamIp);
			}
			else
				CreateDB(iClient, iTarget, sSteamIp);
		}
	}
}

void DoCreateDB(int iClient, int iTarget, int iTrax = 0, Transaction hTxn = null)
{
	if (g_iTargetType[iClient] >= TYPE_GAG)
	{
		if ((g_iTargetMuteType[iTarget] > 0 && g_iTargetType[iClient] >= TYPE_UNGAG) || 
			(g_iTargetMuteType[iTarget] == TYPEMUTE && g_iTargetType[iClient] == TYPE_MUTE) ||
			(g_iTargetMuteType[iTarget] == TYPEGAG && g_iTargetType[iClient] == TYPE_GAG) ||
			(g_iTargetMuteType[iTarget] == TYPESILENCE && g_iTargetType[iClient] == TYPE_SILENCE))
		{
			if (!IsUnMuteUnBan(iClient, g_sTargetMuteSteamAdmin[iTarget]))
			{
				if (iTarget && IsClientInGame(iTarget))
				{
					char sName[MAX_NAME_LENGTH];
					GetClientName(iTarget, sName, sizeof(sName));
					switch(g_iTargetType[iClient])
					{
						case TYPE_GAG, TYPE_MUTE, TYPE_SILENCE:			PrintToChat2(iClient, "%T", "No access mute", iClient, sName);
						case TYPE_UNGAG, TYPE_UNMUTE, TYPE_UNSILENCE:	PrintToChat2(iClient, "%T", "No access un mute", iClient, sName);
					}
				}
				else
				{
					if (!iTarget)
					{
						switch(g_iTargetType[iClient])
						{
							case TYPE_GAG, TYPE_MUTE, TYPE_SILENCE:			PrintToChat2(iClient, "%T", "No access mute", iClient, g_sTarget[iClient][TNAME]);
							case TYPE_UNGAG, TYPE_UNMUTE, TYPE_UNSILENCE: 	PrintToChat2(iClient, "%T", "No access un mute", iClient, g_sTarget[iClient][TNAME]);
						}
					}
				}
				return;
			}
		}
		
		if (iTarget && g_iTargetType[iClient] >= TYPE_UNMUTE && g_iTargetMuteType[iTarget] == 0 && GetClientListeningFlags(iTarget) == VOICE_MUTED)
		{
			SetClientListeningFlags(iTarget, VOICE_NORMAL);
			return;
		}
		else if (iTarget && g_iTargetType[iClient] >= TYPE_UNGAG && g_iTargetMuteType[iTarget] == 0)
			return;
	}

	CreateDB(iClient, iTarget, _, iTrax, hTxn);
}

//------------------------------------------------------------------------------------------------------------------------------
//занесение в бд
void CreateDB(int iClient, int iTarget, char[] sSteamIp = "", int iTrax = 0,  Transaction hTxn = null)
{
	if (iTrax == 2)
	{
		SQL_LockDatabase(g_dDatabase);
		SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
		SQL_UnlockDatabase(g_dDatabase);
		g_dDatabase.Execute(hTxn, SQL_TxnCallback_Success, SQL_TxnCallback_Failure);
		return;
	}
	
#if MADEBUG
	if ((iClient && IsClientInGame(iClient)) && (iTarget && IsClientInGame(iTarget)))
		LogToFile(g_sLogDateBase,"Create bd: client %N, target %N, Type %d, MuteType %d", iClient, iTarget, g_iTargetType[iClient], g_iTargetMuteType[iTarget]);
	else
		LogToFile(g_sLogDateBase,"Create bd: client %d, target %d, Type %d, MuteType %d", iClient, iTarget, g_iTargetType[iClient], g_iTargetMuteType[iTarget]);
#endif
	
	char sBanName[MAX_NAME_LENGTH*2+1],
		 sQuery[1024],
		 sReason[256],
		 sLog[1024],
		 sLength[64],
		 sAdmin_SteamID[MAX_STEAMID_LENGTH],
		 sAdminName[MAX_NAME_LENGTH],
		 sQueryAdmin[512],
		 sQueryTime[226],
		 sServer[256];
		 
	int iTime;
	int iCreated = GetTime();

	if(g_iServerID == -1)
		FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
	else
		IntToString(g_iServerID, sServer, sizeof(sServer));
	
	if (iClient && IsClientInGame(iClient))
	{
		GetClientAuthId(iClient, TYPE_STEAM, sAdmin_SteamID, sizeof(sAdmin_SteamID));
		GetClientName(iClient, sAdminName, sizeof(sAdminName));
		FormatEx(sQueryAdmin, sizeof(sQueryAdmin), "\
				IFNULL((SELECT aid FROM %s_admins a INNER JOIN %s_admins_servers_groups asg ON (a.aid = asg.admin_id AND asg.server_id = %s) \
				WHERE (a.authid REGEXP '^STEAM_[0-9]:%s$') LIMIT 1), 0)", 
			g_sDatabasePrefix, g_sDatabasePrefix, sServer, sAdmin_SteamID[8]);
	}
	else
	{
		strcopy(sAdmin_SteamID, sizeof(sAdmin_SteamID), "STEAM_ID_SERVER");
		if (iTarget && IsClientInGame(iTarget))
			FormatEx(sAdminName, sizeof(sAdminName), "%T", "Server", iTarget);
		else
			FormatEx(sAdminName, sizeof(sAdminName), "%t", "Server");
		strcopy(sQueryAdmin, sizeof(sQueryAdmin), "0");
	}
	
	if (iTarget && IsClientInGame(iTarget))
	{
		GetClientAuthId(iTarget, TYPE_STEAM, g_sTarget[iClient][TSTEAMID], sizeof(g_sTarget[][]));
		GetClientIP(iTarget, g_sTarget[iClient][TIP], sizeof(g_sTarget[][]));
		GetClientName(iTarget, g_sTarget[iClient][TNAME], sizeof(g_sTarget[][]));
		
		if (g_iTargetType[iClient] >= TYPE_GAG && g_iTargetType[iClient] <= TYPE_SILENCE)
			strcopy(g_sTargetMuteSteamAdmin[iTarget], sizeof(g_sTargetMuteSteamAdmin[]), sAdmin_SteamID);
	}
	else
	{
		if (g_bOnileTarget[iClient])
		{
			ReplyToCommand(iClient, "%sNo games %d", MAPREFIX, iTarget);
			return;
		}
	}
	
	strcopy(g_sNameReples[0], sizeof(g_sNameReples[]), g_sTarget[iClient][TNAME]); // ??????

	if (g_iTarget[iClient][TTIME] == -1)
	{
		strcopy(sQueryTime, sizeof(sQueryTime), "((length = '0' OR ends > UNIX_TIMESTAMP()) AND RemoveType IS NULL) OR length = '-1' ORDER BY `bid` DESC LIMIT 1");
		iTime = g_iTarget[iClient][TTIME];
	}
	else
	{
		strcopy(sQueryTime, sizeof(sQueryTime), "(length = '0' OR ends > UNIX_TIMESTAMP()) AND RemoveType IS NULL");
		if (g_iTarget[iClient][TTIME] == 0)
			iTime = g_iTarget[iClient][TTIME];
		else
			iTime = g_iTarget[iClient][TTIME]*60;
	}
	
	FormatVrema(iClient, iTime, sLength, sizeof(sLength));
	
	if (!g_sTarget[iClient][TREASON][0])
		FormatEx(g_sTarget[iClient][TREASON], sizeof(g_sTarget[][]), "%T", "No reason", iClient);

	if (ChekBD(g_dDatabase, "create bd escape"))
	{
		g_dDatabase.Escape(g_sTarget[iClient][TREASON], sReason, sizeof(sReason));
		g_dDatabase.Escape(g_sTarget[iClient][TNAME], sBanName, sizeof(sBanName));
	}
#if MADEBUG
	LogToFile(g_sLogDateBase,"name do %s : posle %s", g_sTarget[iClient][TNAME], sBanName);
#endif

	switch(g_iTargetType[iClient])
	{
		case TYPE_UNBAN:
		{
			if (sSteamIp[0] == 'S')
			{
				FormatEx(sQuery, sizeof(sQuery), "\
						UPDATE `%s_bans` SET `RemovedBy` = %s, `RemoveType` = 'U', `RemovedOn` = UNIX_TIMESTAMP(), `ureason` = '%s' \
						WHERE (`type` = 0 AND `authid` REGEXP '^STEAM_[0-9]:%s$') AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemoveType` IS NULL", 
					g_sDatabasePrefix, sQueryAdmin, sReason, sSteamIp[8]);
				FireOnClientUnBanned(iClient, "", sSteamIp, g_sTarget[iClient][TREASON]);
			}
			else 
			{
				FormatEx(sQuery, sizeof(sQuery), "\
						UPDATE `%s_bans` SET `RemovedBy` = %s, `RemoveType` = 'U', `RemovedOn` = UNIX_TIMESTAMP(), `ureason` = '%s' \
						WHERE (`type` = 1 AND `ip` = '%s') AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemoveType` IS NULL", 
					g_sDatabasePrefix, sQueryAdmin, sReason, sSteamIp);
				FireOnClientUnBanned(iClient, sSteamIp, "", g_sTarget[iClient][TREASON]);
			}
			ShowAdminAction(iClient, "%t", "UnBanned show", "name", sSteamIp);
			FormatEx(sLog, sizeof(sLog), "\"%L\" unbanned \"%s\" (reason \"%s\")", iClient, sSteamIp, g_sTarget[iClient][TREASON]);
		}
		case TYPE_BAN, TYPE_BANIP, TYPE_ADDBAN:
		{
			int iTyp;
			if (g_iTargetType[iClient] == TYPE_BAN || g_iTargetType[iClient] == TYPE_ADDBAN && sSteamIp[0] == 'S')
				iTyp = 0;
			else
				iTyp = 1;
			
			if (g_iTargetType[iClient] <= TYPE_BANIP || g_iTargetType[iClient] == TYPE_ADDBAN && iTarget)
			{
				FormatEx(sQuery, sizeof(sQuery), "\
						INSERT INTO `%s_bans` (`type`, `ip`, `authid`, `name`, `created`, `ends`, `length`, `reason`, `aid`, `adminIp`, `sid`, `country`) \
						VALUES (%d, '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', %s, '%s', %s, ' ')", 
					g_sDatabasePrefix, iTyp, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], sBanName, iTime, iTime, sReason, sQueryAdmin, sAdmin_SteamID, sServer);
				
				FireOnClientBanned(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
				ShowAdminAction(iClient, "%t", "Banned show", "name", g_sTarget[iClient][TNAME], sLength, g_sTarget[iClient][TREASON]);
				if (iTarget)
					CreateSayBanned(sAdminName, iTarget, iCreated, iTime, sLength, g_sTarget[iClient][TREASON]);
				FormatEx(sLog, sizeof(sLog), "\"%L\" %s banned \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", (g_iTargetType[iClient] == TYPE_ADDBAN)?"add":"", iClient, g_sTarget[iClient][TNAME], 
											g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
			}
			else if (g_iTargetType[iClient] == TYPE_ADDBAN)
			{
				FormatEx(sQuery, sizeof(sQuery), "\
						INSERT INTO `%s_bans` (`type`, `ip`, `authid`, `created`, `ends`, `length`, `reason`, `aid`, `adminIp`, `sid`, `country`) \
						VALUES (%d, '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', %s, '%s', %s, ' ')", 
					g_sDatabasePrefix, iTyp, iTyp?sSteamIp:"", !iTyp?sSteamIp:"", iTime, iTime, sReason, sQueryAdmin, sAdmin_SteamID, sServer);
				
				FireOnClientAddBanned(iClient, sSteamIp, "", g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
				ShowAdminAction(iClient, "%t", "Banned show", "name", sSteamIp, sLength, g_sTarget[iClient][TREASON]);
				FormatEx(sLog, sizeof(sLog), "\"%L\" add banned \"%s\" (minutes \"%d\") (reason \"%s\")", iClient, sSteamIp, g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
			}
		}
		case TYPE_GAG, TYPE_MUTE, TYPE_SILENCE:
		{
			int iType;
			bool bSetQ = true,
				bSet = true;
			if (iTarget && g_iTargenMuteTime[iTarget] == -1)
				bSet = false;

			switch(g_iTargetType[iClient])
			{
				case TYPE_GAG:
				{
					iType = TYPEGAG;
					if (bSet)
					{
						if (g_iTargetMuteType[iTarget] == TYPEMUTE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `type` = 3 , `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 1 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);

							bSetQ = false;
						}
						else if (g_iTargetMuteType[iTarget] == TYPEGAG)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `reason` = '%s', `created` = UNIX_TIMESTAMP(), `ends` = UNIX_TIMESTAMP() + %d, \
									`length` = %d, `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 2 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sReason, iTime, iTime, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);
							
							bSetQ = false;
						}
					}
					if (iTarget)
					{
						AddGag(iTarget, iTime);
						PrintToChat2(iTarget, "%T", "Target gag", iTarget, sLength, g_sTarget[iClient][TREASON]);
					}
					FireOnClientMuted(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], TYPEGAG, g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
					ShowAdminAction(iClient, "%t", "Gag show", "name", g_sTarget[iClient][TNAME], sLength, g_sTarget[iClient][TREASON]);
					FormatEx(sLog, sizeof(sLog), "\"%L\" gag \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
										g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
				}
				case TYPE_MUTE:
				{
					iType = TYPEMUTE;
					if (bSet)
					{
						if (g_iTargetMuteType[iTarget] == TYPEGAG)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `type` = 3 , `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 2 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);
							
							bSetQ = false;
						}
						else if (g_iTargetMuteType[iTarget] == TYPEMUTE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `reason` = '%s', `created` = UNIX_TIMESTAMP(), `ends` = UNIX_TIMESTAMP() + %d, \
									`length` = %d, `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 1 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sReason, iTime, iTime, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);
							
							bSetQ = false;
						}
					}
					if (iTarget)
					{
						AddMute(iTarget, iTime);
						PrintToChat2(iTarget, "%T", "Target mute", iTarget, sLength, g_sTarget[iClient][TREASON]);
					}
					FireOnClientMuted(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], TYPEMUTE, g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
					ShowAdminAction(iClient, "%t", "Mute show", "name", g_sTarget[iClient][TNAME], sLength, g_sTarget[iClient][TREASON]);
					FormatEx(sLog, sizeof(sLog), "\"%L\" mute \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
										g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
				}
				case TYPE_SILENCE:
				{
					iType = TYPESILENCE;
					if (bSet)
					{
						if (g_iTargetMuteType[iTarget] == TYPEGAG)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `type` = 3 , `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 2 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);
							
							bSetQ = false;
						}
						else if (g_iTargetMuteType[iTarget] == TYPEMUTE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `type` = 3 , `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 1 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);
							
							bSetQ = false;
						}
						else if (g_iTargetMuteType[iTarget] == TYPESILENCE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `reason` = '%s', `created` = UNIX_TIMESTAMP(), `ends` = UNIX_TIMESTAMP() + %d, \
									`length` = %d, `aid` = %s, `adminIp` = '%s', `sid` = %s \
									WHERE `type` = 3 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND %s", 
								g_sDatabasePrefix, sReason, iTime, iTime, sQueryAdmin, sAdmin_SteamID, sServer, g_sTarget[iClient][TSTEAMID][8], sQueryTime);

							bSetQ = false;
						}
					}
					if (iTarget)
					{
						AddSilence(iTarget, iTime);
						PrintToChat2(iTarget, "%T", "Target silence", iTarget, sLength, g_sTarget[iClient][TREASON]);
					}
					FireOnClientMuted(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], TYPESILENCE, g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
					ShowAdminAction(iClient, "%t", "Silence show", "name", g_sTarget[iClient][TNAME], sLength, g_sTarget[iClient][TREASON]);
					FormatEx(sLog, sizeof(sLog), "\"%L\" silence \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
										g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
				}
			}
			if (iTarget)
			{
				if (iTime > 0)
					g_iTargenMuteTime[iTarget] = iCreated + iTime;
				else
					g_iTargenMuteTime[iTarget] = iTime;
				strcopy(g_sTargetMuteReason[iTarget], sizeof(g_sTargetMuteReason[]), g_sTarget[iClient][TREASON]);
			}
			if(bSetQ)
			{
				FormatEx(sQuery, sizeof(sQuery), "\
						INSERT INTO `%s_comms` (`authid`, `name`, `created`, `ends`, `length`, `reason`, `aid`, `adminIp`, `sid`, `type`) \
						VALUES ('%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', %s, '%s', %s, %d)", 
					g_sDatabasePrefix, g_sTarget[iClient][TSTEAMID], sBanName, iTime, iTime, sReason, sQueryAdmin, sAdmin_SteamID, sServer, iType);
			}
		}
		case TYPE_UNGAG, TYPE_UNMUTE, TYPE_UNSILENCE:
		{
			int iType;
			bool bSetQ = true,
				bSet = true;
			if (iTarget && g_iTargenMuteTime[iTarget] == -1)
			{
				bSet = false;
				bSetQ = false;
			}

			switch(g_iTargetType[iClient])
			{
				case TYPE_UNGAG:
				{
					iType = TYPEGAG;
					if (bSet)
					{
						if (g_iTargetMuteType[iTarget] == TYPESILENCE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` SET `type` = 1, `aid` = %s \
									WHERE `type` = 3 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemoveType` IS NULL", 
								g_sDatabasePrefix, sQueryAdmin, g_sTarget[iClient][TSTEAMID][8]);
							bSetQ = false;
						}
					}
					if (iTarget)
					{
						UnGag(iTarget);
						PrintToChat2(iTarget, "%T", "Target ungag", iTarget);
					}
					FireOnClientUnMuted(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], TYPEGAG, g_sTarget[iClient][TREASON]);
					ShowAdminAction(iClient, "%t", "UnGag show", "name", g_sTarget[iClient][TNAME]);
					FormatEx(sLog, sizeof(sLog), "\"%L\" un gag \"%s (%s IP_%s)\" (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
												g_sTarget[iClient][TIP], g_sTarget[iClient][TREASON]);
				}
				case TYPE_UNMUTE:
				{
					iType = TYPEMUTE;
					if (bSet)
					{
						if (g_iTargetMuteType[iTarget] == TYPESILENCE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` SET `type` = 2, `aid` = %s  \
									WHERE `type` = 3 AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemoveType` IS NULL", 
								g_sDatabasePrefix, sQueryAdmin, g_sTarget[iClient][TSTEAMID][8]);
							bSetQ = false;
						}
					}
					if (iTarget)
					{
						UnMute(iTarget);
						PrintToChat2(iTarget, "%T", "Target unmute", iTarget);
					}
					FireOnClientUnMuted(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], TYPEMUTE, g_sTarget[iClient][TREASON]);
					ShowAdminAction(iClient, "%t", "UnMute show", "name", g_sTarget[iClient][TNAME]);
					FormatEx(sLog, sizeof(sLog), "\"%L\" un mute \"%s (%s IP_%s)\" (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
												g_sTarget[iClient][TIP], g_sTarget[iClient][TREASON]);
				}
				case TYPE_UNSILENCE:
				{
					iType = TYPESILENCE;
					if (bSet)
					{
						if (g_iTargetMuteType[iTarget] < TYPESILENCE)
						{
							FormatEx(sQuery, sizeof(sQuery), "\
									UPDATE `%s_comms` \
									SET `RemovedBy` = %s, `RemoveType` = 'U', `RemovedOn` = UNIX_TIMESTAMP(), `ureason` = '%s' \
									WHERE `authid` REGEXP '^STEAM_[0-9]:%s$' AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemoveType` IS NULL", 
								g_sDatabasePrefix, sQueryAdmin, sReason, g_sTarget[iClient][TSTEAMID][8]);
							bSetQ = false;
						}
					}
					if (iTarget)
					{
						UnSilence(iTarget);
						PrintToChat2(iTarget, "%T", "Target unsilence", iTarget);
					}
					FireOnClientUnMuted(iClient, iTarget, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], g_sTarget[iClient][TNAME], TYPESILENCE, g_sTarget[iClient][TREASON]);
					ShowAdminAction(iClient, "%t", "UnSilence show", "name", g_sTarget[iClient][TNAME]);
					FormatEx(sLog, sizeof(sLog), "\"%L\" un silence \"%s (%s IP_%s)\" (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
												g_sTarget[iClient][TIP], g_sTarget[iClient][TREASON]);
				}
			}
			if(bSetQ)
			{
				FormatEx(sQuery, sizeof(sQuery), "\
						UPDATE `%s_comms` \
						SET `RemovedBy` = %s, `RemoveType` = 'U', `RemovedOn` = UNIX_TIMESTAMP(), `ureason` = '%s' \
						WHERE `type` = %d AND `authid` REGEXP '^STEAM_[0-9]:%s$' AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemoveType` IS NULL", 
					g_sDatabasePrefix, sQueryAdmin, sReason, iType, g_sTarget[iClient][TSTEAMID][8]);
			}
		}
	}
	
	DataPack dPack = new DataPack();
	dPack.WriteCell((!iClient)?0:GetClientUserId(iClient));
	dPack.WriteString(sSteamIp[0]?sSteamIp:g_sTarget[iClient][TNAME]);
	dPack.WriteString(sQuery);

	if (ChekBD(g_dDatabase, "create bd"))
	{
		if (!iTrax)
		{
			SQL_LockDatabase(g_dDatabase);
			SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
			SQL_UnlockDatabase(g_dDatabase);
			//g_dDatabase.SetCharset("utf8");
			g_dDatabase.Query(CreateBdCallback, sQuery, dPack, DBPrio_High);
		}
		else
			hTxn.AddQuery(sQuery, dPack);
	#if MADEBUG
		LogToFile(g_sLogDateBase,"create bd: %s", sQuery);
	#endif
	}
	else
		BekapStart(sQuery);

	LogAction(iClient, -1, sLog);
}

//ответ занисения в бд(прошёл или нет)
public void CreateBdCallback(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	DataPack dPack = view_as<DataPack>(data);
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	char sTargetName[MAX_NAME_LENGTH];
	dPack.ReadString(sTargetName, sizeof(sTargetName));
	
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "CreateBdCallback Query Failed: %s", sError);
		if (sError[0] == 'C' || sError[0] == 'L')
		{
			char sQuery[1024];
			dPack.ReadString(sQuery, sizeof(sQuery));
			BekapStart(sQuery);
		}

		if (iClient && IsClientInGame(iClient))
			PrintToChat2(iClient, "%T", "Failed to bd", iClient, sTargetName);
		else
			ReplyToCommand(iClient, "%s Failed to add to the database %s", MAPREFIX, sTargetName);
	}
	else
	{
		if (iClient && IsClientInGame(iClient))
			PrintToChat2(iClient, "%T", "Added to bd", iClient, sTargetName);
		else
			ReplyToCommand(iClient, "%s Added to the database %s", MAPREFIX, sTargetName);
	}

	g_sTarget[iClient][TSTEAMID][0] = '\0';
	g_sTarget[iClient][TIP][0] = '\0';
	g_sTarget[iClient][TNAME][0] = '\0';
	g_sTarget[iClient][TREASON][0] = '\0';
	
	delete dPack;
}

#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
public void SQL_TxnCallback_Success(Database db, any data, int iNumQueries, Handle[] dbRs, any[] QueryData)
#else
public void SQL_TxnCallback_Success(Database db, any data, int iNumQueries, DBResultSet[] dbRs, any[] QueryData)
#endif
{
	DataPack dPack;
	int iClient;
	char sTargetName[MAX_NAME_LENGTH];
	
	for (int i = 0; i < iNumQueries; i++)
	{
		if (!dbRs[i])
			continue;

		dPack = view_as<DataPack>(QueryData[i]);
		dPack.Reset();
		iClient = GetClientOfUserId(dPack.ReadCell());
		dPack.ReadString(sTargetName, sizeof(sTargetName));
		
		if (iClient && IsClientInGame(iClient))
			PrintToChat2(iClient, "%T", "Added to bd", iClient, sTargetName);
		else
			ReplyToCommand(iClient, "%s Added to the database %s", MAPREFIX, sTargetName);
	}
	
	delete dPack;
}

public void SQL_TxnCallback_Failure(Database db, any data, int iNumQueries, const char[] sError, int iFailIndex, any[] QueryData)
{
	//неверно переписать!!!!!!!!!!!!!
	DataPack dPack = view_as<DataPack>(QueryData[iFailIndex]);
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	char sTargetName[MAX_NAME_LENGTH];
	dPack.ReadString(sTargetName, sizeof(sTargetName));
	
	LogToFile(g_sLogDateBase, "CreateBdCallback Query Failed %d: %s", iFailIndex, sError);

	if (iClient && IsClientInGame(iClient))
		PrintToChat2(iClient, "%T", "Failed to bd", iClient, sTargetName);
	else
		ReplyToCommand(iClient, "%s Failed to add to the database", MAPREFIX);
	
	delete dPack;
}
//------------------------------------------------------------------------------------------------------------------------------
//проверка игрока на бан
void CheckClientBan(int iClient)
{
	char sSteamID[MAX_STEAMID_LENGTH];
	GetClientAuthId(iClient, TYPE_STEAM, sSteamID, sizeof(sSteamID));
		
	if (sSteamID[0] == 'B' || sSteamID[9] == 'L' || !g_dDatabase)
		return;

	if (ChekBD(g_dDatabase, "CheckClientBan"))
	{
		char sQuery[1204],
			sServer[256],
			sSourceSleuth[256],
			sIp[30];
		GetClientIP(iClient, sIp, sizeof(sIp));
		
		if (g_iIgnoreBanServer)
		{
			if(g_iServerID == -1)
				FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
			else
				IntToString(g_iServerID, sServer, sizeof(sServer));
		}
		
		switch(g_iIgnoreBanServer)
		{
			case 0: sServer[0] = '\0';
			case 1:	Format(sServer, sizeof(sServer), " AND a.`sid` = %s", sServer);
			case 2: Format(sServer, sizeof(sServer), " AND (a.`sid` = %s OR a.`sid` = 0)", sServer);
		}
		
		if (!g_bSourceSleuth)
			sSourceSleuth[0] = '\0';
		else
			FormatEx(sSourceSleuth, sizeof(sSourceSleuth), " OR (a.`type` = 0 AND a.`ip` = '%s')", sIp);
		
		FormatEx(sQuery, sizeof(sQuery), "\
				SELECT a.`bid`, a.`length`, a.`created`, a.`reason`, b.`user` FROM `%s_bans` a LEFT JOIN `%s_admins` b ON a.`aid` = b.`aid` \
				WHERE ((a.`type` = 0 AND a.`authid` REGEXP '^STEAM_[0-9]:%s$') OR (a.`type` = 1 AND a.`ip` = '%s')%s) \
				AND (a.`length` = 0 OR a.`ends` > UNIX_TIMESTAMP()) AND a.`RemoveType` IS NULL%s LIMIT 0,1", 
			g_sDatabasePrefix, g_sDatabasePrefix, sSteamID[8], sIp, sSourceSleuth, sServer);

	#if MADEBUG
		LogToFile(g_sLogDateBase, "Checking ban for: %s. QUERY: %s", sSteamID, sQuery);
	#endif
		
		SQL_LockDatabase(g_dDatabase);
		SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
		SQL_UnlockDatabase(g_dDatabase);
		//g_dDatabase.SetCharset("utf8");
		g_dDatabase.Query(VerifyBan, sQuery, GetClientUserId(iClient), DBPrio_High);
	}
	else
		CheckClientAdmin(iClient, sSteamID);
}

public void VerifyBan(Database db, DBResultSet dbRs, const char[] sError, any iUserId)
{
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "Verify Ban Query Failed: %s", sError);
		return;
	}

	int iClient = GetClientOfUserId(iUserId);

	if (!iClient || !IsClientInGame(iClient))
		return;

	char sSteamID[MAX_STEAMID_LENGTH];
	GetClientAuthId(iClient, TYPE_STEAM, sSteamID, sizeof(sSteamID));

	if (dbRs.FetchRow())
	{
		switch (FireOnClientConnectBan(iClient))
		{
			case Plugin_Handled, Plugin_Stop:
			{
				g_bBanClientConnect[iClient] = false;
				CheckClientAdmin(iClient, sSteamID);
				CheckClientMute(iClient, sSteamID);
				return;
			}
		}

		char sReason[256],
			sLength[64],
			sCreated[128],
			sEnds[128],
			sName[MAX_NAME_LENGTH],
			sEName[MAX_NAME_LENGTH*2+1],
			sIP[MAX_IP_LENGTH],
			sQuery[1512],
			sSourceSleuth[256],
			sServer[256];
		int iLength = dbRs.FetchInt(1);
		int iCreated = dbRs.FetchInt(2);
		dbRs.FetchString(3, sReason, sizeof(sReason));

		if(!iLength)
		{
			FormatEx(sLength, sizeof(sLength), "%T", "Permanent", iClient);
			if(g_bBanSayPanel)
				FormatEx(sEnds, sizeof(sEnds), "%T", "No ends", iClient);
		}
		else
		{
			FormatVrema(iClient, iLength, sLength, sizeof(sLength));
			if(g_bBanSayPanel)
				FormatTime(sEnds, sizeof(sEnds), FORMAT_TIME, iCreated + iLength);
		}
		
		FormatTime(sCreated, sizeof(sCreated), FORMAT_TIME, iCreated);	
		GetClientIP(iClient, sIP, sizeof(sIP));
		GetClientName(iClient, sName, sizeof(sName));
		g_dDatabase.Escape(sName, sEName, sizeof(sEName));

		if(g_iServerID == -1)
			FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
		else
			IntToString(g_iServerID, sServer, sizeof(sServer));
		
		if (!g_bSourceSleuth)
			sSourceSleuth[0] = '\0';
		else
			FormatEx(sSourceSleuth, sizeof(sSourceSleuth), " OR (`type` = 0 AND `ip` = '%s')", sIP);

		FormatEx(sQuery, sizeof(sQuery), "\
				INSERT INTO `%s_banlog` (`sid` ,`time` ,`name` ,`bid`) \
				VALUES (%s, UNIX_TIMESTAMP(), '%s', \
				(SELECT `bid` FROM `%s_bans` WHERE ((`type` = 0 AND `authid` REGEXP '^STEAM_[0-9]:%s$') OR (`type` = 1 AND `ip` = '%s')%s) AND `RemoveType` IS NULL LIMIT 0,1))", 
			g_sDatabasePrefix, sServer, sEName, g_sDatabasePrefix, sSteamID[8], sIP, sSourceSleuth);

	#if MADEBUG
		LogToFile(g_sLogDateBase, "Ban log: QUERY: %s", sQuery);
	#endif
		SQL_LockDatabase(g_dDatabase);
		SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
		SQL_UnlockDatabase(g_dDatabase);
		//g_dDatabase.SetCharset("utf8");
		g_dDatabase.Query(SQL_Callback_BanLog, sQuery, _, DBPrio_High);

		g_bBanClientConnect[iClient] = true;
		
	#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
		if (!SQL_IsFieldNull(dbRs, 0))
	#else
 		if (!dbRs.IsFieldNull(0))
	#endif
		{
			char sAdmin[64];
			dbRs.FetchString(4, sAdmin, sizeof(sAdmin));
			if(g_bBanSayPanel)
				CreateTeaxtDialog(iClient, "%T", "Banned Admin panel", iClient, sAdmin, sReason, sCreated, sEnds, sLength, g_sWebsite);
			else
				KickClient(iClient, "%T", "Banned Admin", iClient, sAdmin, sReason, sCreated, sLength, g_sWebsite);
		}
		else
		{
			if(g_bBanSayPanel)
				CreateTeaxtDialog(iClient, "%T", "Banned panel", iClient, sReason, sCreated, sEnds, sLength, g_sWebsite);
			else
				KickClient(iClient, "%T", "Banned", iClient, sReason, sCreated, sLength, g_sWebsite);
		}
		if (g_iServerBanTime > 0)
		{
			DataPack dPack = new DataPack();
			dPack.WriteString(g_bServerBanTyp?sSteamID:sIP);
			CreateTimer(0.5, TimerBan, dPack);
		}
	}
	else
	{
		g_bBanClientConnect[iClient] = false;
		CheckClientAdmin(iClient, sSteamID);
		CheckClientMute(iClient, sSteamID);
	}
}

public void SQL_Callback_BanLog(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_BanLog Query Failed: %s", sError);
}

//проверка игрока на мут
void CheckClientMute(int iClient, char[] sSteamID)
{
	char sQuery[1204],
		sServer[256];
		
	if (g_iIgnoreMuteServer)
	{
		if (g_iServerID == -1)
			FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
		else
			IntToString(g_iServerID, sServer, sizeof(sServer));
	}
	
	switch(g_iIgnoreMuteServer)
	{
		case 0: sServer[0] = '\0';
		case 1:	Format(sServer, sizeof(sServer), " AND `sid` = %s", sServer);
		case 2: Format(sServer, sizeof(sServer), " AND (`sid` = %s OR `sid` = 0)", sServer);
	}
	
	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT (c.`ends` - UNIX_TIMESTAMP()), c.`type`, c.`length`, c.`reason`, a.`authid` \
			FROM `%s_comms` AS c \
			LEFT JOIN `%s_admins` AS a ON a.`aid` = c.`aid` \
			LEFT JOIN `%s_srvgroups` AS g ON g.`name` = a.`srv_group` \
			WHERE `RemoveType` IS NULL  AND c.`authid` REGEXP '^STEAM_[0-9]:%s$' \
			AND (`length` = 0 OR `ends` > UNIX_TIMESTAMP())%s", 
		g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, sSteamID[8], sServer);

#if MADEBUG
	LogToFile(g_sLogDateBase, "Check Mute: %s. QUERY: %s", sSteamID, sQuery);
#endif
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	g_dDatabase.Query(VerifyMute, sQuery, GetClientUserId(iClient), DBPrio_High);
}

public void VerifyMute(Database db, DBResultSet dbRs, const char[] sError, any iUserId)
{
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "Verify Mute failed: %s", sError);
		return;
	}

	int iClient = GetClientOfUserId(iUserId);
	
	if (!iClient || !IsClientInGame(iClient))
		return;

	if (dbRs.FetchRow())
	{
		int iEndTime = dbRs.FetchInt(0);
		int iType = dbRs.FetchInt(1);
		int iTime = dbRs.FetchInt(2);
		dbRs.FetchString(3, g_sTargetMuteReason[iClient], sizeof(g_sTargetMuteReason[]));
		dbRs.FetchString(4, g_sTargetMuteSteamAdmin[iClient], sizeof(g_sTargetMuteSteamAdmin[]));
			
	#if MADEBUG
		LogToFile(g_sLogDateBase, "CheckClientMute: set %N, time %d, type %d", iClient, iTime, iType);
	#endif
			
		g_iTargetMuteType[iClient] = iType;
			
		if(!iTime)
			g_iTargenMuteTime[iClient] = iTime;
		else
			g_iTargenMuteTime[iClient] = iEndTime + GetTime();
		
		FireOnClientConnectGetMute(iClient, iType, g_iTargenMuteTime[iClient], g_sTargetMuteReason[iClient]);
		
		switch (iType)
		{
			case TYPEMUTE:		AddMute(iClient, g_iTargenMuteTime[iClient]);
			case TYPEGAG: 		AddGag(iClient, g_iTargenMuteTime[iClient]);
			case TYPESILENCE:	AddSilence(iClient, g_iTargenMuteTime[iClient]);
		}
	}
	else
	{
		g_iTargetMuteType[iClient] = 0;
		FireOnClientConnectGetMute(iClient, 0, -1, "");
	#if MADEBUG
		LogToFile(g_sLogDateBase, "CheckClientMute: set %N type 0", iClient);
	#endif
	}
}

//-----------------------------------------------------------------------------------------------------------------------------
// работа с админами
void AdminHash()
{
	if (ChekBD(g_dDatabase, "AdminHash"))
	{
		DeleteFile(g_sGroupsLoc);
		DeleteFile(g_sAdminsLoc);
		DeleteFile(g_sOverridesLoc);
		DumpAdminCache(AdminCache_Groups, true);
		DumpAdminCache(AdminCache_Overrides, true);
		DumpAdminCache(AdminCache_Admins, true);
		
		char sQuery[204];

		FormatEx(sQuery, sizeof(sQuery), "\
				SELECT `type`, `name`, `flags` \
				FROM `%s_overrides`", 
			g_sDatabasePrefix);

		SQL_LockDatabase(g_dDatabase);
		SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
		SQL_UnlockDatabase(g_dDatabase);
		//g_dDatabase.SetCharset("utf8");
		g_dDatabase.Query(OverridesDone, sQuery, _, DBPrio_High);
	}
	else
	{
		ReadOverrides();
		ReadGroups();
		ReadUsers();
	}
}

public void OverridesDone(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "Failed to retrieve overrides from the database, %s", sError);
	else
	{
		KeyValues kvOverrides = new KeyValues("overrides");
		
		char sFlags[32], 
			 sName[64],
			 sType[64];
		while (dbRs.FetchRow())
		{
			dbRs.FetchString(0, sType, sizeof(sType));
			dbRs.FetchString(1, sName, sizeof(sName));
			dbRs.FetchString(2, sFlags, sizeof(sFlags));

			if (!sFlags[0])
			{
				sFlags[0] = ' ';
				sFlags[1] = '\0';
			}

			if (StrEqual(sType, "command"))
				kvOverrides.SetString(sName, sFlags);
			else if (StrEqual(sType, "group"))
			{
				Format(sName, sizeof(sName), "@%s", sName);
				kvOverrides.SetString(sName, sFlags);
			}
			
		#if MADEBUG
			LogToFile(g_sLogDateBase, "Adding override (%s, %s, %s)", sType, sName, sFlags);
		#endif
		}
		
		kvOverrides.Rewind();
		kvOverrides.ExportToFile(g_sOverridesLoc);
		delete kvOverrides;
	}
	
	ReadOverrides();
	
	char sQuery[254];

	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT `name`, `flags`, `immunity`, `maxbantime`, `maxmutetime` \
			FROM `%s_srvgroups` ORDER BY `id`", 
		g_sDatabasePrefix);
#if MADEBUG
	LogToFile(g_sLogDateBase, "GroupsDone:QUERY: %s", sQuery);
#endif
	SQL_LockDatabase(g_dDatabase);
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	SQL_UnlockDatabase(g_dDatabase);
	//g_dDatabase.SetCharset("utf8");
	g_dDatabase.Query(GroupsDone, sQuery, _, DBPrio_High);
}

public void GroupsDone(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "Failed to retrieve groups from the database, %s", sError);
	else
	{
		char sGrpName[128], 
			sGrpFlags[32];
		int iImmunity,
			iMaxBanTime = -1,
			iMaxMuteTime = -1;
	#if MADEBUG
		int	iGrpCount = 0;
	#endif
		KeyValues kvGroups = new KeyValues("groups");

		while (dbRs.MoreRows)
		{
			dbRs.FetchRow();
		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (SQL_IsFieldNull(dbRs, 0))
		#else
			if (dbRs.IsFieldNull(0))
		#endif
				continue;

			dbRs.FetchString(0, sGrpName, sizeof(sGrpName));
			dbRs.FetchString(1, sGrpFlags, sizeof(sGrpFlags));
			iImmunity = dbRs.FetchInt(2);
		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (!SQL_IsFieldNull(dbRs, 3))
		#else
			if (!dbRs.IsFieldNull(3))
		#endif
				iMaxBanTime = dbRs.FetchInt(3);
		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (!SQL_IsFieldNull(dbRs, 4))
		#else
			if (!dbRs.IsFieldNull(4))
		#endif
				iMaxMuteTime = dbRs.FetchInt(4);
			
			TrimString(sGrpName);
			TrimString(sGrpFlags);
			
			// Ignore empty rows..
			if (!sGrpName[0])
				continue;
			
			kvGroups.JumpToKey(sGrpName, true);
			if (sGrpFlags[0])
				kvGroups.SetString("flags", sGrpFlags);
			if (iImmunity)
				kvGroups.SetNum("immunity", iImmunity);
			
			kvGroups.SetNum("maxbantime", iMaxBanTime);
			kvGroups.SetNum("maxmutetime", iMaxMuteTime);
				
			kvGroups.Rewind();
			
		#if MADEBUG
			LogToFile(g_sLogDateBase, "Add %s Group", sGrpName);
			iGrpCount++;
		#endif
		}
		
		kvGroups.ExportToFile(g_sGroupsLoc);
		delete kvGroups;
		
	#if MADEBUG
		LogToFile(g_sLogDateBase, "Finished loading %i groups.", iGrpCount);
	#endif
	}
	
	// Load the group overrides
	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT sg.`name`, so.`type`, so.`name`, so.`access` \
			FROM `%s_srvgroups_overrides` so LEFT JOIN `%s_srvgroups` sg ON sg.`id` = so.`group_id` ORDER BY sg.`id`", 
		g_sDatabasePrefix, g_sDatabasePrefix);
#if MADEBUG
	LogToFile(g_sLogDateBase, "LoadGroupsOverrides:QUERY: %s", sQuery);
#endif
	g_dDatabase.Query(LoadGroupsOverrides, sQuery, _, DBPrio_High);
}

public void LoadGroupsOverrides(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "Failed to retrieve group overrides from the database, %s", sError);
	else
	{
		char sGroupName[128],
			sType[16],
			sCommand[64],
			sAllowed[16];
		
		KeyValues kvGroups = new KeyValues("groups");
		kvGroups.ImportFromFile(g_sGroupsLoc);

		while (dbRs.FetchRow())
		{
		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (SQL_IsFieldNull(dbRs, 0))
		#else
			if (dbRs.IsFieldNull(0))
		#endif
				continue;
			
			dbRs.FetchString(0, sGroupName, sizeof(sGroupName));
			TrimString(sGroupName);
			if (!sGroupName[0])
				continue;
			
			dbRs.FetchString(1, sType, sizeof(sType));
			dbRs.FetchString(2, sCommand, sizeof(sCommand));
			dbRs.FetchString(3, sAllowed, sizeof(sAllowed));

			if (kvGroups.JumpToKey(sGroupName))
			{
				kvGroups.JumpToKey("overrides", true);
				if (StrEqual(sType, "command"))
					kvGroups.SetString(sCommand, sAllowed);
				else if (StrEqual(sType, "group"))
				{
					Format(sCommand, sizeof(sCommand), "@%s", sCommand);
					kvGroups.SetString(sCommand, sAllowed);
				}
				kvGroups.Rewind();
			}
			
		#if MADEBUG
			LogToFile(g_sLogDateBase, "Adding group %s override (%s, %s)", sGroupName, sType, sCommand);
		#endif
		}
		
		kvGroups.ExportToFile(g_sGroupsLoc);
		delete kvGroups;
	}
	
	ReadGroups();
	
	char sQuery[1204],
		sServer[256];
	if(g_iServerID == -1)
		FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
	else
		IntToString(g_iServerID, sServer, sizeof(sServer));

	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT `authid`, `srv_password`, (SELECT `name` FROM `%s_srvgroups` WHERE `name` = `srv_group` AND `flags` != '') \
			AS `srv_group`, `srv_flags`, `user`, `immunity`, `expired`, `extraflags`,  \
			(SELECT `flags` FROM `%s_groups` WHERE `gid` = a.`gid`) AS `flags` \
			FROM `%s_admins_servers_groups` AS asg LEFT JOIN `%s_admins` AS a ON a.`aid` = asg.`admin_id` \
			WHERE (`expired` > UNIX_TIMESTAMP() OR `expired` = 0 OR `expired` = NULL) \
			AND `authid` != 'STEAM_ID_SERVER' \
			AND ((`server_id` = %s OR `srv_group_id` = ANY (SELECT `group_id` FROM `%s_servers_groups` \
			WHERE `server_id` = %s))) GROUP BY `aid`, `authid`, `srv_password`, `srv_group`, `srv_flags`, `user`", 
		g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, sServer, g_sDatabasePrefix, sServer);
#if MADEBUG
	LogToFile(g_sLogDateBase, "AdminsDone:QUERY: %s", sQuery);
#endif
	SQL_LockDatabase(g_dDatabase);
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	SQL_UnlockDatabase(g_dDatabase);
	//g_dDatabase.SetCharset("utf8");
	g_dDatabase.Query(AdminsDone, sQuery, _, DBPrio_High);
}

public void AdminsDone(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	//SELECT authid, srv_password , srv_group, srv_flags, user
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "Failed to retrieve admins from the database, %s", sError);
	else
	{
		char sAuthType[] = "steam",
			sIdentity[66],
			sPassword[66],
			sGroups[256],
			sFlags[32],
			sName[66];
	#if MADEBUG
		int iAdmCount;
	#endif
		int iImmunity,
			iExpire,
			iExtraflags,
			iExtraflagsGroup,
			iWebFlag[2];
		KeyValues kvAdmins = new KeyValues("admins");
		
		while (dbRs.MoreRows)
		{
			dbRs.FetchRow();
		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (SQL_IsFieldNull(dbRs, 0))
		#else
			if (dbRs.IsFieldNull(0))
		#endif
				continue; // Sometimes some rows return NULL due to some setups
			
			dbRs.FetchString(0, sIdentity, sizeof(sIdentity));
			dbRs.FetchString(1, sPassword, sizeof(sPassword));
			dbRs.FetchString(2, sGroups, sizeof(sGroups));
			dbRs.FetchString(3, sFlags, sizeof(sFlags));
			dbRs.FetchString(4, sName, sizeof(sName));
			
			iImmunity = dbRs.FetchInt(5);
			iExpire = dbRs.FetchInt(6);
			iExtraflags = dbRs.FetchInt(7);

		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (!SQL_IsFieldNull(dbRs, 8))
		#else
			if (!dbRs.IsFieldNull(8))
		#endif
				iExtraflagsGroup = dbRs.FetchInt(8);
			else
				iExtraflagsGroup = 0;
			
			TrimString(sName);
			ReplaceString(sName, sizeof(sName), "/", "_"); // костыль из-за бага
			TrimString(sIdentity);
			TrimString(sGroups);
			TrimString(sFlags);
			
			kvAdmins.JumpToKey(sName, true);
				
			kvAdmins.SetString("auth", sAuthType);
			
			if (g_iGameTyp >= GAMETYP_CSGO) // костыль из-за говно игры
				ReplaceString(sIdentity, sizeof(sIdentity), "STEAM_0", "STEAM_1");
			else
				ReplaceString(sIdentity, sizeof(sIdentity), "STEAM_1", "STEAM_0");
			kvAdmins.SetString("identity", sIdentity);
				
			if (sFlags[0])
				kvAdmins.SetString("flags", sFlags);
				
			if (sGroups[0])
				kvAdmins.SetString("group", sGroups);
				
			if (sPassword[0])
				kvAdmins.SetString("password", sPassword);
				
			if (iImmunity)
				kvAdmins.SetNum("immunity", iImmunity);
			
			if (iExpire)
				kvAdmins.SetNum("expire", iExpire);
			
			
			iWebFlag = GetWebFlag(iExtraflags, iExtraflagsGroup);
			kvAdmins.SetNum("setingsadmin", iWebFlag[1]);
			kvAdmins.SetNum("unbanmute", iWebFlag[0]);
				
			kvAdmins.Rewind();
			
		#if MADEBUG
			LogToFile(g_sLogDateBase, "Add %s (%s) admin (Flags %s, Groups %s, Immunity %i, Expire %i, setingsadmin %i, unbanmute %i, Extraflags %i, ExtraflagsGroup %i)", 
						sName, sIdentity, sFlags, sGroups, iImmunity, iExpire, iWebFlag[1], iWebFlag[0], iExtraflags, iExtraflagsGroup);
			++iAdmCount;
		#endif
		}
		
		kvAdmins.ExportToFile(g_sAdminsLoc);
		delete kvAdmins;
	#if MADEBUG
		LogToFile(g_sLogDateBase, "Finished loading %i admins.", iAdmCount);
	#endif
	}
	
	ReadUsers();
}
//-------------------------------------------------------------------------------------------------------------
// бекап бд
void BekapStart(char[] sQuery)
{
	char sQuerys[2524],
		sEQuery[2124];
	g_dSQLite.Escape(sQuery, sEQuery, sizeof(sEQuery));
	FormatEx(sQuerys, sizeof(sQuerys), "INSERT INTO `bekap` (`query`, `time`) VALUES ('%s', %d)", sEQuery, GetTime());
	g_dSQLite.Query(SQL_Callback_AddQueryBekap, sQuerys, _, DBPrio_Low);
	
#if MADEBUG
	LogToFile(g_sLogDateBase, "BekapStart:QUERY: %s", sQuery);
#endif
	
	if (g_hTimerBekap == null)
		g_hTimerBekap = CreateTimer(g_fRetryTime, TimerBekap, _, TIMER_REPEAT);
}

public void SQL_Callback_AddQueryBekap(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_AddQueryBekap: %s", sError);
}

void SentBekapInBd()
{
	char sQuery[1024];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, `query` FROM `bekap`");
	g_dSQLite.Query(SQL_Callback_QueryBekap, sQuery, _, DBPrio_Low);
}

public void SQL_Callback_QueryBekap(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_QueryBekap Query Failed: %s", sError);

	if (dbRs.RowCount)
	{
		char sQuery[1024];
		int iId;
		while(dbRs.MoreRows)
		{
			if(!dbRs.FetchRow())
				continue;

			iId = dbRs.FetchInt(0);
			dbRs.FetchString(1, sQuery, sizeof(sQuery));
		#if MADEBUG
			LogToFile(g_sLogDateBase, "QueryBekap:QUERY: %s", sQuery);
		#endif
			SQL_LockDatabase(g_dDatabase);
			SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
			SQL_UnlockDatabase(g_dDatabase);
			//g_dDatabase.SetCharset("utf8");
			g_dDatabase.Query(CheckCallbackBekap, sQuery, iId, DBPrio_Low); // байда с зависанием скрипта
		}
	}
}

public void CheckCallbackBekap(Database db, DBResultSet dbRs, const char[] sError, any iId)
{
	if (!dbRs || sError[0])
	{
		if (g_hTimerBekap == null)
			g_hTimerBekap = CreateTimer(g_fRetryTime, TimerBekap, _, TIMER_REPEAT);
		LogToFile(g_sLogDateBase, "CheckCallbackBekap Query Failed: %s", sError);
	}
	else
		DeleteBekap(iId);
}

void DeleteBekap(int iId)
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `bekap` WHERE `id` = %d", iId);
	g_dSQLite.Query(SQL_Callback_DeleteBekap, sQuery, _, DBPrio_Low);
#if MADEBUG
	LogToFile(g_sLogDateBase, "DeleteBekap:QUERY: %s", sQuery);
#endif
}

public void SQL_Callback_DeleteBekap(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_DeleteBekap Query Failed: %s", sError);
}

void CheckBekapTime()
{
	char sQuery[1024];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, `time` FROM `bekap`");
	g_dSQLite.Query(SQL_Callback_CheckBekapTime, sQuery, _, DBPrio_Low);
}

public void SQL_Callback_CheckBekapTime(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "SQL_Callback_CheckBekapTime Query Failed: %s", sError);

	if (dbRs.RowCount)
	{
		int iId,
			iTimeBekap;
			
		int iTime = GetTime();
		while(dbRs.MoreRows)
		{
			if(!dbRs.FetchRow())
				continue;
			
			iId = dbRs.FetchInt(0);
			iTimeBekap = dbRs.FetchInt(1);
			
			if (iTimeBekap + 604800 > iTime)
				DeleteBekap(iId);
		}
	}
}
//-----------------------------------------------------------------------------------------------------------------------------
// репорт
void SetBdReport(int iClient, const char[] sReason)
{
	if (!iClient)
		return;

	int iTarget	= GetClientOfUserId(g_iTargetReport[iClient]);
	
	if(!iTarget)
	{
		PrintToChat2(iClient, "%T", "No Client Game", iClient);
		return;
	}

	char sReportName[MAX_NAME_LENGTH],
		 sEReportName[MAX_NAME_LENGTH*2+1],
		 sQuery[1024],
		 sEReason[556],
		 sReport_SteamID[MAX_STEAMID_LENGTH],
		 sReportIp[MAX_IP_LENGTH],
		 sSteamID[MAX_STEAMID_LENGTH],
		 sIp[MAX_IP_LENGTH],
		 sName[MAX_NAME_LENGTH],
		 sEName[MAX_NAME_LENGTH*2+1],
		 sServer[256],
		 sModId[256];

	GetClientAuthId(iClient, TYPE_STEAM, sSteamID, sizeof(sSteamID));
	GetClientIP(iClient, sIp, sizeof(sIp));
	GetClientName(iClient, sName, sizeof(sName));
	
	GetClientAuthId(iTarget, TYPE_STEAM, sReport_SteamID, sizeof(sReport_SteamID));
	GetClientIP(iTarget, sReportIp, sizeof(sReportIp));
	GetClientName(iTarget, sReportName, sizeof(sReportName));
	
	g_dDatabase.Escape(sReason, sEReason, sizeof(sEReason));
	g_dDatabase.Escape(sReportName, sEReportName, sizeof(sEReportName));
	g_dDatabase.Escape(sName, sEName, sizeof(sEName));

	if(g_iServerID == -1)
	{
		FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
		FormatEx(sModId, sizeof(sModId), "IFNULL ((SELECT `modid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
	}
	else
	{
		IntToString(g_iServerID, sServer, sizeof(sServer));
		FormatEx(sModId, sizeof(sModId), "IFNULL ((SELECT `modid` FROM `%s_servers` WHERE `sid` = %d LIMIT 1), 0)", g_sDatabasePrefix, g_iServerID);
	}
	
	FormatEx(sQuery, sizeof(sQuery), "\
			INSERT INTO  `%s_submissions` (`submitted`, `SteamId`, `name`, `email`, `ModID`, `reason`, `ip`, `subname`, `sip`, `archiv`, `server`) \
			VALUES (UNIX_TIMESTAMP(), '%s', '%s', '%s', %s, '%s', '%s', '%s', '%s', 0, %s)", 
		g_sDatabasePrefix, sReport_SteamID, sEReportName, sSteamID, sModId, sEReason, sIp, sEName, sReportIp, sServer);
	
	if (ChekBD(g_dDatabase, "SetBdReport"))
	{
		DataPack dPack = new DataPack();
		dPack.WriteCell(GetClientUserId(iClient));
		dPack.WriteString(sReportName);
		dPack.WriteString(sQuery);
		
	#if MADEBUG
		LogToFile(g_sLogDateBase, "SetBdReport:QUERY: %s", sQuery);
	#endif
		SQL_LockDatabase(g_dDatabase);
		SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
		SQL_UnlockDatabase(g_dDatabase);
		//g_dDatabase.SetCharset("utf8");
		g_dDatabase.Query(CheckCallbackReport, sQuery, dPack, DBPrio_High);
	}
	else
		BekapStart(sQuery);
}

public void CheckCallbackReport(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	DataPack dPack = view_as<DataPack>(data);
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	char sReportName[MAX_NAME_LENGTH];
	dPack.ReadString(sReportName, sizeof(sReportName));
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "SQL_CheckCallbackReport Query Failed: %s", sError);
		if (sError[0] == 'C' || sError[0] == 'L')
		{
			char sQuery[1024];
			dPack.ReadString(sQuery, sizeof(sQuery));
			BekapStart(sQuery);
		}
	}

	if (iClient)
		PrintToChat2(iClient, "%T", "Yes report", iClient, sReportName);

	delete dPack;
}
//---------------------------------------------------------------------------------------------------------------------
public Action OnBanClient(int iClient, int iTime, int iFlags, const char[] sReason, const char[] kick_message, const char[] command, any source)
{
	if (IsClientInGame(iClient))
	{
		GetClientAuthId(iClient, TYPE_STEAM, g_sTarget[0][TSTEAMID], sizeof(g_sTarget[][]));
		GetClientIP(iClient, g_sTarget[0][TIP], sizeof(g_sTarget[][]));
		GetClientName(iClient, g_sTarget[0][TNAME], sizeof(g_sTarget[][]));
		strcopy(g_sTarget[0][TREASON], sizeof(g_sTarget[][]), sReason);
		g_iTarget[0][TTIME] = iTime;
		
	#if MADEBUG
		LogToFile(g_sLogDateBase, "OnBanClient: set CheckBanInBd");
	#endif
		g_bOnileTarget[0] = false;
		if (iFlags & BANFLAG_AUTO || iFlags & BANFLAG_AUTHID)
		{
			CheckBanInBd(0, iClient, 1, g_sTarget[0][TSTEAMID]);
			g_iTargetType[0] = TYPE_BAN;
		}
		else if (iFlags & BANFLAG_IP)
		{
			CheckBanInBd(0, iClient, 1, g_sTarget[0][TIP]);
			g_iTargetType[0] = TYPE_BANIP;
		}
	}
	
	return Plugin_Continue;
}

public Action OnBanIdentity(const char[] sIdentity, int iTime, int flags, const char[] sReason, const char[] command, any source)
{
	char sBuffer[MAX_IP_LENGTH];
	strcopy(sBuffer, sizeof(sBuffer), sIdentity);
	strcopy(g_sTarget[0][TREASON], sizeof(g_sTarget[][]), sReason);
	g_iTarget[0][TTIME] = iTime;
	
	if (sBuffer[0] == '[')
		ConvecterSteam3ToSteam2(sBuffer);
	
	g_iTargetType[0] = TYPE_ADDBAN;
		
#if MADEBUG
	LogToFile(g_sLogDateBase, "OnBanIdentity: set CheckBanInBd");
#endif
	CheckBanInBd(0, 0, 1, sBuffer);
	
	return Plugin_Continue;
}

public Action OnRemoveBan(const char[] sIdentity, int flags, const char[] command, any source)
{
	char sBuffer[MAX_IP_LENGTH];
	strcopy(sBuffer, sizeof(sBuffer), sIdentity);
	
	if (sBuffer[0] == '[')
		ConvecterSteam3ToSteam2(sBuffer);
	
	g_iTargetType[0] = TYPE_UNBAN;

#if MADEBUG
	LogToFile(g_sLogDateBase, "OnRemoveBan: set CheckBanInBd");
#endif	
	CheckBanInBd(0, 0, 0, sBuffer);

	return Plugin_Continue;
}
//------------------------------------------------------------------------------------------
// управление админами
void BDAddAdmin(int iClient, bool bFlag = false)
{
	char sQuery[1056],
		 sFlags[56];
	
	if (bFlag)
		strcopy(sFlags, sizeof(sFlags), g_sAddAdminInfo[iClient][ADDFLAG]);
	else
	{
		sFlags[0] = '\0';
		for (int i = 0; i < 21; i++)
		{
			if (g_bAddAdminFlag[iClient][i])
				Format(sFlags, sizeof(sFlags), "%s%s", g_sAddAdminFlag[i], sFlags);
		}
	}
	
	FormatEx(sQuery, sizeof(sQuery), "\
			INSERT INTO `%s_admins` (`user`, `authid`, `immunity`, `srv_flags`, `password`, `gid`, `email`, `extraflags`, `expired`) \
			VALUES ('%s', '%s', %d, '%s', SHA(CONCAT('SourceBans', SHA('%s'))), 0, '', 0, %d);", 
		g_sDatabasePrefix, g_sAddAdminInfo[iClient][ADDNAME], g_sAddAdminInfo[iClient][ADDSTEAM], g_iAddAdmin[iClient][ADDIMUN], sFlags, 
		g_sAddAdminInfo[iClient][ADDPASS], g_iAddAdmin[iClient][ADDTIME]);

#if MADEBUG
	LogToFile(g_sLogDateBase, "BDAddAdmin:QUERY: %s", sQuery);
#endif
	SQL_LockDatabase(g_dDatabase);
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	SQL_UnlockDatabase(g_dDatabase);
	//g_dDatabase.SetCharset("utf8");
	g_dDatabase.Query(CallbackAddAdmin, sQuery, GetClientUserId(iClient), DBPrio_High);
}

public void CallbackAddAdmin(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	int iClient = GetClientOfUserId(data);
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "CallbackAddAdmin: %s", sError);
		if (iClient)
			PrintToChat2(iClient, "%T", "Failed add admin", iClient, g_sAddAdminInfo[iClient][ADDNAME]);
		return;
	}
	
	if (iClient && IsClientInGame(iClient))
		PrintToChat2(iClient, "%T", "Ok add admin bd", iClient, g_sAddAdminInfo[iClient][ADDNAME], g_sAddAdminInfo[iClient][ADDPASS]);

	BDCheckAdmins(iClient, 0);
}

void BDCheckAdmins(int iClient, int iTyp)
{
	char sQuery[256];
	
	DataPack dPack = new DataPack();
	dPack.WriteCell(GetClientUserId(iClient));
	dPack.WriteCell(iTyp);

	FormatEx(sQuery, sizeof(sQuery), "\
			SELECT `aid`, `srv_group` FROM `%s_admins` \
			WHERE `authid` REGEXP '^STEAM_[0-9]:%s$'", 
		g_sDatabasePrefix, g_sAddAdminInfo[iClient][ADDSTEAM][8]);

#if MADEBUG
	LogToFile(g_sLogDateBase, "BDCheckAdmins:QUERY: %s", sQuery);
#endif
	SQL_LockDatabase(g_dDatabase);
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	SQL_UnlockDatabase(g_dDatabase);
	//g_dDatabase.SetCharset("utf8");
	g_dDatabase.Query(CallbackCheckAdmin, sQuery, dPack, DBPrio_High);
}

public void CallbackCheckAdmin(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	DataPack dPack = view_as<DataPack>(data);
	dPack.Reset();
	int iClient = GetClientOfUserId(dPack.ReadCell());
	int iTyp = dPack.ReadCell();
	delete dPack;

	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "CallbackCheckAdmins Query Failed: %s", sError);

	if (!iClient && !IsClientInGame(iClient))
		return;

	if (iTyp < 3 && iTyp > 0) // удаление 1 тока с севрера, 2 полностью
	{
		if (dbRs.RowCount)
		{
			dbRs.FetchRow();
			int iId = dbRs.FetchInt(0);
			BDDelAdmin(iClient, iId, iTyp);
		}
		else
			PrintToChat2(iClient, "%T", "No admin sb", iClient, g_sAddAdminInfo[iClient][ADDNAME]);
	}
	else // добавление
	{
		if (dbRs.RowCount)
		{
			dbRs.FetchRow();
			int iId = dbRs.FetchInt(0);
			char sGroup[124];
		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (!SQL_IsFieldNull(dbRs, 1))
		#else
			if (!dbRs.IsFieldNull(1))
		#endif
				dbRs.FetchString(1, sGroup, sizeof(sGroup));
			else
				sGroup[0] = '\0';

			BDAddServerAdmin(iClient, iId, sGroup); // добавляется просто админ на сервер.
		}
		else
		{
			if (iTyp == 3)
				BDAddAdmin(iClient, true);
			else
			{
				ResetFlagAddAdmin(iClient);// сброс флагов
				MenuAddAdninFlag(iClient);
			}
		}
	}
}

void BDAddServerAdmin(int iClient, int iId, char[] sGroup)
{
	if(sGroup[0])
		Format(sGroup, 124, "IFNULL ((SELECT `id` FROM `%s_srvgroups` WHERE `name` = '%s' LIMIT 1), -1)", g_sDatabasePrefix, sGroup);
	else
		strcopy(sGroup, 124, "-1");
	
	char sServer[256],
		 sQuery[556];
	if(g_iServerID == -1)
		FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
	else
		IntToString(g_iServerID, sServer, sizeof(sServer));
	
	
	FormatEx(sQuery, sizeof(sQuery), "\
			INSERT INTO `%s_admins_servers_groups` (`admin_id`, `group_id`, `srv_group_id`, `server_id`) \
			VALUES (%d, %s, -1, %s)", 
		g_sDatabasePrefix, iId, sGroup, sServer);

#if MADEBUG
	LogToFile(g_sLogDateBase, "BDAddServerAdmin:QUERY: %s", sQuery);
#endif
	SQL_LockDatabase(g_dDatabase);
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	SQL_UnlockDatabase(g_dDatabase);
	//g_dDatabase.SetCharset("utf8");
	g_dDatabase.Query(CallbackAddServerAdmin, sQuery, GetClientUserId(iClient), DBPrio_High);
}

public void CallbackAddServerAdmin(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	int iClient = GetClientOfUserId(data);
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "CallbackAddServerAdmin Query Failed: %s", sError);
		if (iClient)
			PrintToChat2(iClient, "%T", "Failed add admin", iClient, g_sAddAdminInfo[iClient][ADDNAME]);
		return;
	}
	
	if (iClient && IsClientInGame(iClient))
		PrintToChat2(iClient, "%T", "Ok add admin server", iClient, g_sAddAdminInfo[iClient][ADDNAME]);

	AdminHash();
}

void BDDelAdmin(int iClient, int iId, int iTyp)
{
	char sQuery[556];
	if (iTyp == 1)
	{
		char sServer[256];
		if(g_iServerID == -1)
			FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
		else
			IntToString(g_iServerID, sServer, sizeof(sServer));
		
		FormatEx(sQuery, sizeof(sQuery), "\
				DELETE FROM `%s_admins_servers_groups` WHERE `admin_id` = %d AND `server_id` = %s", 
			g_sDatabasePrefix, iId, sServer);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery), "\
			DELETE a1, a2 FROM `%s_admins` AS a1 LEFT JOIN `%s_admins_servers_groups` AS a2 \
			ON (a1.`aid` = a2.`admin_id`) WHERE a1.`aid` = %d;", 
		g_sDatabasePrefix, g_sDatabasePrefix, iId);
	}

#if MADEBUG
	LogToFile(g_sLogDateBase, "BDDelAdmin:QUERY: %s", sQuery);
#endif
	SQL_LockDatabase(g_dDatabase);
	SQL_FastQuery(g_dDatabase, "SET NAMES 'utf8'");
	SQL_UnlockDatabase(g_dDatabase);
	//g_dDatabase.SetCharset("utf8");
	g_dDatabase.Query(CallbackDelAdmin, sQuery, GetClientUserId(iClient), DBPrio_High);
}

public void CallbackDelAdmin(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	int iClient = GetClientOfUserId(data);
	if (!dbRs || sError[0])
	{
		LogToFile(g_sLogDateBase, "CallbackDelAdmin Query Failed: %s", sError);
		if (iClient && IsClientInGame(iClient))
			PrintToChat2(iClient, "%T", "Failed del admin", iClient, g_sAddAdminInfo[iClient][ADDNAME]);
		return;
	}
	
	if (iClient && IsClientInGame(iClient))
		PrintToChat2(iClient, "%T", "Ok del admin", iClient, g_sAddAdminInfo[iClient][ADDNAME]);

	AdminHash();
}
//--------------------------------------------------------------------------------------------------------
// активность админа (в разработке в вебе, или забит хер на это)
/*void BDSetActivityAdmin(int iClient, char[] sSteamID)
{
	char sQuery[1056],
		sServer[256];
		
	int iPlayed = RoundToCeil(GetClientTime(iClient));
	int iTime = GetTime();
	
	if(g_iServerID == -1)
		FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
	else
		IntToString(g_iServerID, sServer, sizeof(sServer));
	
	FormatEx(sQuery, sizeof(sQuery), "\
			INSERT INTO `%s_admins_activity` (`aid`, `sid`, `ctime`, `played`) \
			VALUES (IFNULL((SELECT aid FROM %s_admins a INNER JOIN %s_admins_servers_groups asg ON (a.aid = asg.admin_id AND asg.server_id = %s) \
			WHERE (a.authid REGEXP '^STEAM_[0-9]:%s$') LIMIT 1), 0), %s, %d, %d)", 
		g_sDatabasePrefix, g_sDatabasePrefix, g_sDatabasePrefix, sServer, sSteamID[8], sServer, iTime - iPlayed, iPlayed);
		
	g_dDatabase.Query(CallbackSetActivityAdmin, sQuery);
}

public void CallbackSetActivityAdmin(Database db, DBResultSet dbRs, const char[] sError, any data)
{
	if (!dbRs || sError[0])
		LogToFile(g_sLogDateBase, "CallbackSetActivityAdmin Query Failed: %s", sError);
}*/