enum GroupState
{
	GroupState_None,
	GroupState_Groups,
	GroupState_InGroup,
	GroupState_Overrides,
}

enum GroupPass
{
	GroupPass_Invalid,
	GroupPass_First,
	GroupPass_Second,
}

static SMCParser g_smcGroupParser;
static GroupId g_idGroup = INVALID_GROUP_ID;
static GroupState g_iGroupState = GroupState_None;
static GroupPass g_iGroupPass = GroupPass_Invalid;
static bool g_bNeedReparse = false;


static SMCParser g_smcUserParser;
static char g_sCurAuth[64],
	g_sCurIdent[64],
	g_sCurName[64],
	g_sCurPass[64];
static int g_iCurFlags,
	g_iCurImmunity,
	g_iCurExpire,
	g_iWebFlagSetingsAdmin,
	g_iWebFlagUnBanMute;

static SMCParser g_smcOverrideParser;

#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
public int OnRebuildAdminCache(AdminCachePart acPart)
#else
public void OnRebuildAdminCache(AdminCachePart acPart)
#endif
{
	if (g_iAdminUpdateCache == 3 && g_dDatabase)
		AdminHash();
	else
	{
		switch(acPart)
		{
			case AdminCache_Overrides: 	ReadOverrides();
			case AdminCache_Groups: 	ReadGroups();
			case AdminCache_Admins: 	ReadUsers();
		}
	}
}
//-----------------------------------------------------------------------------------------------------
public SMCResult ReadGroups_NewSection(SMCParser smc, const char[] sName, bool opt_quotes)
{
	if (g_iGroupState == GroupState_None)
	{
		if (StrEqual(sName, "groups", false))
			g_iGroupState = GroupState_Groups;
	} 
	else if (g_iGroupState == GroupState_Groups)
	{
	#if MADEBUG
		if ((g_idGroup = CreateAdmGroup(sName)) == INVALID_GROUP_ID)
		{
			if ((g_idGroup = FindAdmGroup(sName)) == INVALID_GROUP_ID)
				LogToFile(g_sLogAdmin, "Find & Create no group (%s)", sName);
			else
				LogToFile(g_sLogAdmin, "Find yes group (grup %d, %s)", g_idGroup, sName);
		}
		else
			LogToFile(g_sLogAdmin, "Create yes group (grup %d, %s)", g_idGroup, sName);
	#else
		if ((g_idGroup = CreateAdmGroup(sName)) == INVALID_GROUP_ID)
			g_idGroup = FindAdmGroup(sName);
	#endif
		g_iGroupState = GroupState_InGroup;
	} 
	else if (g_iGroupState == GroupState_InGroup)
	{
		if (StrEqual(sName, "overrides", false))
			g_iGroupState = GroupState_Overrides;
	} 
	
	return SMCParse_Continue;
}

public SMCResult ReadGroups_KeyValue(SMCParser smc, const char[] sKey, const char[] sValue, bool key_quotes, bool value_quotes)
{
	if (g_idGroup == INVALID_GROUP_ID)
		return SMCParse_Continue;

	AdminFlag admFlag;
	char sGroupID[12];
	FormatEx(sGroupID, sizeof(sGroupID), "%d", g_idGroup);
	int iValue = StringToInt(sValue);
	
	if (g_iGroupPass == GroupPass_First)
	{
		if (g_iGroupState == GroupState_InGroup)
		{
			if (StrEqual(sKey, "flags"))
			{
				for (int i = 0; i < strlen(sValue); i++)
				{
					if (!FindFlagByChar(sValue[i], admFlag))
						continue;

				#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
					SetAdmGroupAddFlag(g_idGroup, admFlag, true);
				#else
 					g_idGroup.SetFlag(admFlag, true);
				#endif
				}
			#if MADEBUG
				LogToFile(g_sLogAdmin, "Load group flag override (grup %d, %s %s)", g_idGroup, sKey, sValue);
			#endif
			}
			else if (StrEqual(sKey, "maxbantime"))
				g_tGroupBanTimeMax.SetValue(sGroupID, iValue, false);
			else if (StrEqual(sKey, "maxmutetime"))
				g_tGroupMuteTimeMax.SetValue(sGroupID, iValue, false);
			else if (StrEqual(sKey, "immunity"))
				g_bNeedReparse = true;

		} 
		else if (g_iGroupState == GroupState_Overrides)
		{
			OverrideRule overRule = Command_Deny;
			
			if (StrEqual(sValue, "allow"))
				overRule = Command_Allow;
			
			if (sKey[0] == '@')
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				AddAdmGroupCmdOverride(g_idGroup, sKey[1], Override_CommandGroup, overRule);
			#else
 				g_idGroup.AddCommandOverride(sKey[1], Override_CommandGroup, overRule);
			#endif
 			else
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				AddAdmGroupCmdOverride(g_idGroup, sKey, Override_Command, overRule);
			#else
 				g_idGroup.AddCommandOverride(sKey, Override_Command, overRule);
			#endif
			
		#if MADEBUG
			LogToFile(g_sLogAdmin, "Load group command override (group %d, %s, %s)", g_idGroup, sKey, sValue);
		#endif
		}
	}
	else if (g_iGroupPass == GroupPass_Second && g_iGroupState == GroupState_InGroup)
	{
		/* Check for immunity again, core should handle double inserts */
		if (StrEqual(sKey, "immunity"))
		{
			/* If it's a sValue we know about, use it */
			if (StrEqual(sValue, "*"))
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				SetAdmGroupImmunityLevel(g_idGroup, 2);
			#else
 				g_idGroup.ImmunityLevel = 2;
			#endif
			else if (StrEqual(sValue, "$"))
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				SetAdmGroupImmunityLevel(g_idGroup, 1);
			#else
 				g_idGroup.ImmunityLevel = 1;
			#endif
			else
			{
				int iLevel;
				if (StringToIntEx(sValue, iLevel))
				#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
					SetAdmGroupImmunityLevel(g_idGroup, iLevel);
				#else
 					g_idGroup.ImmunityLevel = iLevel;
				#endif
				else
				{
					GroupId idGroup;
					if (sValue[0] == '@')
						idGroup = FindAdmGroup(sValue[1]);
					else
						idGroup = FindAdmGroup(sValue);
					
					if (idGroup != INVALID_GROUP_ID)
					#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
						SetAdmGroupImmuneFrom(g_idGroup, idGroup);
					#else
 						g_idGroup.AddGroupImmunity(idGroup);
					#endif
					else
						LogToFile(g_sLogAdmin, "Unable to find group: \"%s\"", sValue);
				}
			}
		#if MADEBUG
			LogToFile(g_sLogAdmin, "Load group add immunity level (%d, %s, %s)", g_idGroup, sKey, sValue);
		#endif
		}
	}
	
	return SMCParse_Continue;
}

public SMCResult ReadGroups_EndSection(SMCParser smc)
{
	if (g_iGroupState == GroupState_Overrides)
		g_iGroupState = GroupState_InGroup;
	else if (g_iGroupState == GroupState_InGroup)
	{
		g_iGroupState = GroupState_Groups;
		g_idGroup = INVALID_GROUP_ID;
	} 
	else if (g_iGroupState == GroupState_Groups)
		g_iGroupState = GroupState_None;
	
	return SMCParse_Continue;
}

static void InternalReadGroups(const char[] sPath, GroupPass grPass)
{
	/* Set states */
	g_iGroupState = GroupState_None;
	g_idGroup = INVALID_GROUP_ID;
	g_iGroupPass = grPass;
	g_bNeedReparse = false;

	int iLine;
	SMCError err = g_smcGroupParser.ParseFile(sPath, iLine);
	if (err != SMCError_Okay)
	{
		char sError[256];
		g_smcGroupParser.GetErrorString(err, sError, sizeof(sError));
		LogToFile(g_sLogAdmin, "Could not parse file (line %d, file \"%s\"):", iLine, sPath);
		LogToFile(g_sLogAdmin, "Parser encountered error: %s", sError);
	}
}

void ReadGroups()
{
	if (!g_smcGroupParser)
	{
		g_smcGroupParser = new SMCParser();
		g_smcGroupParser.OnEnterSection = ReadGroups_NewSection;
		g_smcGroupParser.OnKeyValue = ReadGroups_KeyValue;
		g_smcGroupParser.OnLeaveSection = ReadGroups_EndSection;
	}
		
	if(FileExists(g_sGroupsLoc))
	{
		InternalReadGroups(g_sGroupsLoc, GroupPass_First);
		if (g_bNeedReparse)
			InternalReadGroups(g_sGroupsLoc, GroupPass_Second);
	
		FireOnFindLoadingAdmin(AdminCache_Groups);
	}
}
//----------------------------------------------------------------------------------------------------
public SMCResult ReadUsers_NewSection(SMCParser smc, const char[] sName, bool opt_quotes)
{
	//if (!StrEqual(sName, "admins", false))

	strcopy(g_sCurName, sizeof(g_sCurName), sName);
	g_sCurAuth[0] = '\0';
	g_sCurIdent[0] = '\0';
	g_sCurPass[0] = '\0';
	g_aGroupArray.Clear();
	g_iCurFlags = 0;
	g_iCurImmunity = 0;
	g_iCurExpire = 0;
	g_iWebFlagSetingsAdmin = 0;
	g_iWebFlagUnBanMute = 0;
	
	return SMCParse_Continue;
}

public SMCResult ReadUsers_KeyValue(SMCParser smc, const char[] sKey, const char[] sValue, bool key_quotes, bool value_quotes)
{
	if (StrEqual(sKey, "auth"))
		strcopy(g_sCurAuth, sizeof(g_sCurAuth), sValue);
	else if (StrEqual(sKey, "identity"))
		strcopy(g_sCurIdent, sizeof(g_sCurIdent), sValue);
	else if (StrEqual(sKey, "password")) 
		strcopy(g_sCurPass, sizeof(g_sCurPass), sValue);
	else if (StrEqual(sKey, "group")) 
	{
		GroupId idGroup = FindAdmGroup(sValue);
		if (idGroup == INVALID_GROUP_ID)
			LogToFile(g_sLogAdmin, "Unknown group \"%s\"", sValue);
		else
		{
		#if MADEBUG
			LogToFile(g_sLogAdmin, "Admin %s group %s %d", g_sCurName, sValue, idGroup);
		#endif
			g_aGroupArray.Push(idGroup);
		}
	} 
	else if (StrEqual(sKey, "flags")) 
	{
		AdminFlag admFlag;
		
		for (int i = 0; i < strlen(sValue); i++)
		{
			if (!FindFlagByChar(sValue[i], admFlag))
				LogToFile(g_sLogAdmin, "Invalid admFlag detected: %c", sValue[i]);
			else
				g_iCurFlags |= FlagToBit(admFlag);
		}
	} 
	else if (StrEqual(sKey, "immunity"))
	{
		if(sValue[0])
			g_iCurImmunity = StringToInt(sValue);
		else
			g_iCurImmunity = 0;
	}
	else if (StrEqual(sKey, "expire"))
	{
		if(sValue[0])
			g_iCurExpire = StringToInt(sValue);
		else
			g_iCurExpire = 0;
	}
	else if (StrEqual(sKey, "setingsadmin"))
	{
		if(sValue[0])
			g_iWebFlagSetingsAdmin = StringToInt(sValue);
		else
			g_iWebFlagSetingsAdmin = 0;
	}
	else if (StrEqual(sKey, "unbanmute"))
	{
		if(sValue[0])
			g_iWebFlagUnBanMute = StringToInt(sValue);
		else
			g_iWebFlagUnBanMute = 0;
	}
	
	return SMCParse_Continue;
}

public SMCResult ReadUsers_EndSection(SMCParser smc)
{
	if (g_sCurIdent[0] && g_sCurAuth[0])
	{
		if (!g_iCurExpire || g_iCurExpire > GetTime())
		{
		
			AdminFlag admFlags[26];
			AdminId idAdmin;
			
			if ((idAdmin = FindAdminByIdentity(g_sCurAuth, g_sCurIdent)) != INVALID_ADMIN_ID)
			{
			#if MADEBUG
				LogToFile(g_sLogAdmin, "Find admin %s yes (%d, auth %s, %s)", g_sCurName, idAdmin, g_sCurAuth, g_sCurIdent);
			#endif
			}
			else
			{
				idAdmin = CreateAdmin(g_sCurName);
			#if MADEBUG
				LogToFile(g_sLogAdmin, "Create new admin %s (%d, auth %s, %s)", g_sCurName, idAdmin, g_sCurAuth, g_sCurIdent);
			#endif
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				if (!BindAdminIdentity(idAdmin, g_sCurAuth, g_sCurIdent))
			#else
 				if (!idAdmin.BindIdentity(g_sCurAuth, g_sCurIdent))
			#endif
				{
					RemoveAdmin(idAdmin);
					LogToFile(g_sLogAdmin, "Failed to bind auth \"%s\" to identity \"%s\"", g_sCurAuth, g_sCurIdent);
					return SMCParse_Continue;
				}
			}
			
		#if MADEBUG
			LogToFile(g_sLogAdmin, "Add admin %s expire %d", g_sCurName, g_iCurExpire);
		#endif
			AddAdminExpire(idAdmin, g_iCurExpire);
			
			
			GroupId idGroup;
			int iMaxBanTime,
				iMaxMuteTime,
				iBanTime,
				iMuteTime;
			char sGroupID[12],
				sAdminID[12];
			FormatEx(sAdminID, sizeof(sAdminID), "%d", idAdmin);
			int iGroupSize = g_aGroupArray.Length;
			if (!iGroupSize)
			{
				iMaxBanTime = -1;
				iMaxMuteTime = -1;
			}
			else
			{
				for (int i = 0; i < iGroupSize; i++)
				{
					idGroup = g_aGroupArray.Get(i);
					
					FormatEx(sGroupID, sizeof(sGroupID), "%d", idGroup);
					if (g_tGroupBanTimeMax.GetValue(sGroupID, iBanTime))
					{
						if (!iMaxBanTime)
							iMaxBanTime = iBanTime;
						else if (iBanTime < iMaxBanTime)
							iMaxBanTime = iBanTime;
					}
					else
						iMaxBanTime = -1;

					if (g_tGroupMuteTimeMax.GetValue(sGroupID, iMuteTime))
					{
						if (!iMaxMuteTime)
							iMaxMuteTime = iMuteTime;
						else if (iMuteTime < iMaxMuteTime)
							iMaxMuteTime = iMuteTime;
					}
					else
						iMaxMuteTime = -1;
						
				#if MADEBUG
					#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
					if (AdminInheritGroup(idAdmin, idGroup))
					#else
					if (idAdmin.InheritGroup(idGroup))
					#endif
						LogToFile(g_sLogAdmin, "Admin %s add group %d", g_sCurName, idGroup);
					else
						LogToFile(g_sLogAdmin, "Admin %s no add group %d", g_sCurName, idGroup);
				#else
					#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
					AdminInheritGroup(idAdmin, idGroup);
					#else
					idAdmin.InheritGroup(idGroup);
					#endif
				#endif
				}
			}
			g_tAdminBanTimeMax.SetValue(sAdminID, iMaxBanTime, false);
			g_tAdminMuteTimeMax.SetValue(sAdminID, iMaxMuteTime, false);

			g_tWebFlagSetingsAdmin.SetValue(sAdminID, g_iWebFlagSetingsAdmin, false);
			g_tWebFlagUnBanMute.SetValue(sAdminID, g_iWebFlagUnBanMute, false);

			if(g_sCurPass[0])
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				SetAdminPassword(idAdmin, g_sCurPass);
			#else
 				idAdmin.SetPassword(g_sCurPass);
			#endif

		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
			if (GetAdminImmunityLevel(idAdmin) < g_iCurImmunity)
				SetAdminImmunityLevel(idAdmin, g_iCurImmunity);
		#else
			if (idAdmin.ImmunityLevel < g_iCurImmunity)
				idAdmin.ImmunityLevel = g_iCurImmunity;
		#endif
			
			int iFlags = FlagBitsToArray(g_iCurFlags, admFlags, sizeof(admFlags));
			for (int i = 0; i < iFlags; i++)
			#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 7
				SetAdminFlag(idAdmin, admFlags[i], true);
			#else
 				idAdmin.SetFlag(admFlags[i], true);
			#endif
			
		#if MADEBUG
			LogToFile(g_sLogAdmin, "Load yes admin (name %s, auth %s, ident %s, flag %d, imuni %d, expire %d, max ban time %d, max mute time %d, web flag setings %d, web flag un ban mute %d)", 
						g_sCurName, g_sCurAuth, g_sCurIdent, g_iCurFlags, g_iCurImmunity, g_iCurExpire, iMaxBanTime, iMaxMuteTime, g_iWebFlagSetingsAdmin, g_iWebFlagUnBanMute);
		#endif
		}
		else
		{
		#if MADEBUG
			LogToFile(g_sLogAdmin, "Load no admin (name %s, auth %s, ident %s, flag %d, imuni %d, expire %d, web flag setings %d, web flag un ban mute %d)", 
						g_sCurName, g_sCurAuth, g_sCurIdent, g_iCurFlags, g_iCurImmunity, g_iCurExpire, g_iWebFlagSetingsAdmin, g_iWebFlagUnBanMute);
		#endif
			LogToFile(g_sLogAdmin, "Failed to create admin %s", g_sCurName);
		}
	}
	
	return SMCParse_Continue;
}

void ReadUsers()
{
	if (!g_smcUserParser)
	{
		g_smcUserParser = new SMCParser();
		g_smcUserParser.OnEnterSection = ReadUsers_NewSection;
		g_smcUserParser.OnKeyValue = ReadUsers_KeyValue;
		g_smcUserParser.OnLeaveSection = ReadUsers_EndSection;
	}

	if(FileExists(g_sAdminsLoc))
	{
		g_tAdminBanTimeMax.Clear();
		g_tAdminMuteTimeMax.Clear();
		g_tWebFlagSetingsAdmin.Clear();
		g_tWebFlagUnBanMute.Clear();
		g_tAdminsExpired.Clear();
		int iLine;
		SMCError err = g_smcUserParser.ParseFile(g_sAdminsLoc, iLine);
		if (err != SMCError_Okay)
		{
			char sError[256];
			g_smcUserParser.GetErrorString(err, sError, sizeof(sError));
			LogToFile(g_sLogAdmin, "Could not parse file (line %d, file \"%s\"):", iLine, g_sAdminsLoc);
			LogToFile(g_sLogAdmin, "Parser encountered error: %s", sError);
		}
		
		g_tGroupBanTimeMax.Clear();
		g_tGroupMuteTimeMax.Clear();
		
		if (g_bReshashAdmin)
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientInGame(i) && !IsFakeClient(i))
				{
					RunAdminCacheChecks(i);
					NotifyPostAdminCheck(i);
				}
			}
			g_bReshashAdmin = false;
		}
		
		FireOnFindLoadingAdmin(AdminCache_Admins);
	}
}
//-------------------------------------------------------------------------------------------

public SMCResult ReadOverrides_NewSection(SMCParser smc, const char[] sName, bool opt_quotes)
{
	return SMCParse_Continue;
}

public SMCResult ReadOverrides_KeyValue(SMCParser smc, const char[] sKey, const char[] sValue, bool key_quotes, bool value_quotes)
{
	if(!sKey[0])
		return SMCParse_Continue;
	
	int iFlags = ReadFlagString(sValue);
	
	if (sKey[0] == '@')
		AddCommandOverride(sKey[1], Override_CommandGroup, iFlags);
	else
		AddCommandOverride(sKey, Override_Command, iFlags);
	
#if MADEBUG
	LogToFile(g_sLogAdmin, "Load overrid (%s, %s)", sKey, sValue);
#endif
	
	return SMCParse_Continue;
}

public SMCResult ReadOverrides_EndSection(SMCParser smc)
{
	return SMCParse_Continue;
}

void ReadOverrides()
{
	if (!g_smcOverrideParser)
	{
		g_smcOverrideParser = new SMCParser();
		g_smcOverrideParser.OnEnterSection = ReadOverrides_NewSection;
		g_smcOverrideParser.OnKeyValue = ReadOverrides_KeyValue;
		g_smcOverrideParser.OnLeaveSection = ReadOverrides_EndSection;
	}

	if(FileExists(g_sOverridesLoc))
	{
		int iLine;
		SMCError err = g_smcOverrideParser.ParseFile(g_sOverridesLoc, iLine);
		if (err != SMCError_Okay)
		{
			char sError[256];
			g_smcOverrideParser.GetErrorString(err, sError, sizeof(sError));
			LogToFile(g_sLogAdmin, "Could not parse file (line %d, file \"%s\"):", iLine, g_sOverridesLoc);
			LogToFile(g_sLogAdmin, "Parser encountered error: %s", sError);
		}
		
		FireOnFindLoadingAdmin(AdminCache_Overrides);
	}
}