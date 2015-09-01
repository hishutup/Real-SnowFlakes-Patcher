{
This is an automated patcher for Mangaclub's Real Skyrim Snowflakes - Vivid Snow
SupportedWeathers are listed in the INI file.

Created by Hishutup with the guidance of Mator.

Thanks to Mator for some of his functions.


ChangeLog(1.55->1.6)
*Added FormID Lists - not 100% happy with the implementation but it works for now
}
unit userscript;
uses 'Check For Errors';

const
  cVer='1.6';//This is the version of the script, not the main mod
  cDashes = '-----------------------------------------------------------------------------------';
	
  //Debugging Options
  doDebugINI=false;//Displays the info that is read from the ini
  doDebugEffects=false;//Displays the info being loading into the effects list
  doDebugProcess=false;//Display info for the record handling process
  doDebugFormIDLIsts=false;//Displays the FormID Lists
	
  //Please do not use this unless requested by either Mangaclub or Hishy
  doScan=false; //Scan for weathers with the snow flags
	
  cINIFile='Real Snowflakes Patcher.ini';//Ini File Name
  cPatchFile='Vivid Snow.esp';//Patch File to use.
 
var
  sScriptFailedReason: String;//Script failed toggle
  slEffect, slWeather, slFormList, slAppliedWeathers: TStringList;//Global StringLists
  iPatchFile: IInterface;//Stores the Patch File

//
//Basic Functions from mteFunctions
//=============================================================================================================   
function FileByName(s: string): IInterface;
var
  i: integer;
begin
  Result := nil;
  for i := 0 to FileCount - 1 do begin
    if GetFileName(FileByIndex(i)) = s then begin
      Result := FileByIndex(i);
      break;
    end;
  end;
end;

function HexFormID(e: IInterface): string;
var
  s: string;
begin
  s := GetElementEditValues(e, 'Record Header\FormID');
  if SameText(Signature(e), '') then 
    Result := '00000000'
  else  
    Result := Copy(s, Pos('[' + Signature(e) + ':', s) + Length(Signature(e)) + 2, 8);
end;

function ElementByIP(e: IInterface; ip: string): IInterface;
var
  i, index: integer;
  path: TStringList;
begin
  // replace forward slashes with backslashes
  ip := StringReplace(ip, '/', '\', [rfReplaceAll]);
  
  // prepare path stringlist delimited by backslashes
  path := TStringList.Create;
  path.Delimiter := '\';
  path.StrictDelimiter := true;
  path.DelimitedText := ip;
  
  // traverse path
  for i := 0 to Pred(path.count) do begin
    if Pos('[', path[i]) > 0 then begin
      index := StrToInt(GetTextIn(path[i], '[', ']'));
      e := ElementByIndex(e, index);
    end
    else
      e := ElementByPath(e, path[i]);
  end;
  
  // set result
  Result := e;
end;

function geev(e: IInterface; ip: string): string;
begin
  Result := GetEditValue(ElementByIP(e, ip));
end;

function genv(e: IInterface; ip: string): variant;
begin
  Result := GetNativeValue(ElementByIP(e, ip));
end;

procedure senv(e: IInterface; ip: string; val: variant);
begin
  SetNativeValue(ElementByIP(e, ip), val);
end;

procedure AddMastersToList(f: IInterface; var lst: TStringList);
var
  masters, master: IInterface;
  i: integer;
  s: string;
begin
  // add file
  s := GetFileName(f);
  if (lst.IndexOf(s) = -1) then lst.Add(s);
  
  // add file's masters
  masters := ElementByPath(ElementByIndex(f, 0), 'Master Files');
  if Assigned(masters) then begin
    for i := 0 to ElementCount(masters) - 1 do begin
      s := geev(ElementByIndex(masters, i), 'MAST');
      if (lst.IndexOf(s) = -1) then lst.Add(s);
    end;
  end;
end;

procedure AddMastersToFile(f: IInterface; lst: TStringList; silent: boolean);
var
  masters, master: IInterface;
  i: integer;
  s: string;
  slCurrentMasters: TStringList;
begin
  // create local stringlist
  slCurrentMasters := TStringList.Create;
  
  // AddMasterIfMissing will attempt to add the masters to the file.
  if not silent then AddMessage('    Adding masters to '+GetFileName(f)+'...');
  for i := 0 to lst.Count - 1 do begin
    if (Lowercase(lst[i]) <> Lowercase(GetFileName(f))) then
      AddMasterIfMissing(f, lst[i]);
  end;
  
  // AddMasterIfMissing won't add the masters if they have been removed
  // in the current TES5Edit session, so a manual re-adding process is
  // used.  This process can't fully replace AddMasterIfMissing without
  // causing problems.  It only works for masters that have been removed
  // in the current TES5Edit session.
  masters := ElementByPath(ElementByIndex(f, 0), 'Master Files');
  if not Assigned(masters) then begin
    Add(f, ElementByIndex(f, 0), 'Master Files');
    masters := ElementByPath(ElementByIndex(f, 0), 'Master Files');
  end;
  for i := 0 to ElementCount(masters) - 1 do begin
    s := geev(ElementByIndex(masters, i), 'MAST');
    slCurrentMasters.Add(s);
  end;
  for i := 0 to lst.Count - 1 do begin
    if (Lowercase(lst[i]) <> Lowercase(GetFileName(f))) and (slCurrentMasters.IndexOf(lst[i]) = -1) then begin
      master := ElementAssign(masters, HighInteger, nil, False);
      SetElementEditValues(master, 'MAST', lst[i]);
      AddMessage('      +Re-added master: '+lst[i]);
    end;
  end;
  
  // free stringlist
  slCurrentMasters.Free;
end;

function RecordByHexFormID(id: string): IInterface;
var
  f: IInterface;
begin
  f := FileByLoadOrder(StrToInt('$' + Copy(id, 1, 2)));
  Result := RecordByFormID(f, StrToInt('$' + id), true);
end;

procedure SetListEditValues(e: IInterface; ip: string; values: TStringList);
var
  i: integer;
  list, newelement: IInterface;
begin
  // exit if values is empty
  if values.Count = 0 then exit;
  
  list := ElementByIP(e, ip);
  // clear element list except for one element
  While ElementCount(list) > 1 do
    RemoveByIndex(list, 0, true);
  
  // create elements and populate the list
  for i := 0 to values.Count - 1 do begin
    newelement := ElementAssign(list, HighInteger, nil, False);
    try 
      SetEditValue(newelement, values[i]);
    except on Exception do
      Remove(newelement); // remove the invalid/failed element
    end;
  end;
  Remove(ElementByIndex(list, 0));
end;

procedure slev(e: IInterface; ip: string; values: TStringList);
begin
  SetListEditValues(e, ip, values);
end;

//
//Initialization
//=============================================================================================================
procedure InitialSetup;
begin
  iPatchFile := FileByName(cPatchFile);//Load the PatchFile's IInterface
  AddMessage('The current Script Version is: '+cVer);//Print the Script version
  AddMessage(cDashes);//Dashes
  
  if wbAppName <> 'TES5' then begin //Check for Skyrim
    sScriptFailedReason := 'This is a Skyrim only script, terminating script now.';
    exit;
  end;
  
  if GetFileName(iPatchFile) = '' then begin //Check for Patch File
    sScriptFailedReason := 'You are missing '+cPatchFile+'. Please reinstal Vivid Snow, terminating script now.';
    exit;
  end;
  
  if HasGroup(iPatchFile, 'WTHR') then begin //Check for Weather Group in Patch File
    sScriptFailedReason := 'Found previously patched weathers. Please reinstal Vivid Snow, terminating script now.';
    exit;
  end;
  
  if HasGroup(iPatchFile, 'FLST') then begin//Checks for FormID Lists
    sScriptFailedReason := 'Found previously patched weathers. Please reinstal Vivid Snow, terminating script now.';
  end;
  
  if not CheckINI then begin //Check for INI File
    sScriptFailedReason := 'You are missing '+cINIFile+'. Please reinstal the "Edit Scripts" folder from the mod archive, terminating script now.';
    exit;
  end;
end;
 
//
//Debug Handling
//============================================================================================================= 
procedure DebugINIMessage(s: string);
begin
  if doDebugINI then AddMessage(s);
end;

procedure DebugEffectsMessage(s: string);
begin
  if doDebugEffects then AddMessage(s);
end;

procedure DebugProcessMessage(s: string);
begin
  if doDebugProcess then AddMessage(s);
end;

procedure DebugFormListMessage(s: string);
begin
  if doDebugFormIDLIsts then AddMessage(s);
end;

//
//File Handling
//=============================================================================================================

function CheckINI: Boolean;
var
  sFullPath: string;
begin
  sFullPath := FileSearch(cINIFile, ScriptsPath);
  Result := sFullPath <> '';
end;

procedure LoadINI;
var
  ini: TMemIniFile;
  slCat, slValues: TStringsList;
  iCat, iVal: Int;
  sCategory, sValue: String;
begin
  slCat := TStringList.Create;
  slValues := TStringList.Create;
  ini := TMemIniFile.Create(ScriptsPath + cINIFile);
  DebugINIMessage('Reading INI Now...');
  DebugINIMessage('  The current INI version is: '+ini.ReadString('General', 'Ver', 'Invaild!')); //ReadINI Version
  ini.ReadSection('Effects', slCat);//Load Value Names
  for iCat := 0 to Pred(slCat.Count) do begin
    sCategory := slCat[iCat];
    DebugINIMessage('  Currently Reading the Category: '+sCategory);
    slEffect.Add(sCategory+'='+''); //'' is going to be the Visual Effect's FormID
    slValues.CommaText := ini.ReadString('Effects',sCategory,'');
    for iVal := 0 to Pred(slValues.Count) do begin
      sValue := slValues[iVal];
      DebugINIMessage('    Loading: '+sValue);
      slWeather.Add(sValue+'='+sCategory);
    end;
    slValues.Clear;
  end;
  slValues.Free;
  slCat.Free;
  ini.Free;
  DebugINIMessage('  Done Reading INI.');
end;

//
//StringLists Handling
//=============================================================================================================
procedure CreateStringLists;
begin
  slWeather := TStringList.Create;//EDID=Effect
  slEffect := TStringList.Create;//Effect=FormID
  slFormList := TStringList.Create; //EDID=FormID
  slAppliedWeathers := TStringList.Create; //Weather e
end;

procedure FreeStringLists;
begin
  slWeather.Free;
  slEffect.Free;
  slFormList.Free;
  slAppliedWeathers.Free;
end;

procedure LoadEffects;
var
  i, iIndex: Int;
  g, e: IInterface;
  sEDID, sFormID: String;
begin
  DebugEffectsMessage('Finding Effects FormIDs');
  g := GroupBySignature(iPatchFile, 'RFCT');
  for i := 0 to Pred(ElementCount(g)) do begin
    e := ElementByIndex(g, i);
    sEDID := EditorID(e);
    iIndex := slEffect.IndexOfName(sEDID);
    if iIndex = -1 then begin 
      AddMessage('    Couldn''t Find the Index of: '+sEDID);
      continue;
    end;
    sFormID := HexFormID(e);
    if sFormID = '00000000' then begin
      AddMessage('    Something went wrong with sFormID for: '+sEDID);
      continue;
    end;
    DebugEffectsMessage('  Adding '+sFormID+' to '+slEffect.Names[iIndex]);
    slEffect.ValueFromIndex[iIndex] := sFormID;
  end;
end;

//
//Record Handling
//=============================================================================================================
procedure CreateFormIDLists;
var
  i: Integer;
  sEffect, sFormID: String;
  g, rec: IInterface;
begin
  DebugFormListMessage('Starting to create FormID Lists.');
  if not HasGroup(iPatchFile, 'FLST') then begin
    Add(iPatchFile,'FLST', True);
    DebugFormListMessage('  Creating FormID List Group');
  end;
  for i := 0 to Pred(slWeather.Count) do begin
    if slFormList.IndexOfName(slWeather.ValueFromIndex[i]+'_List') = -1 then slFormList.Add(slWeather.ValueFromIndex[i]+'_List'+'='+'');
  end;
  g := GroupBySignature(iPatchFile, 'FLST');
  for i := 0 to Pred(slFormList.Count) do begin
    sEffect := slFormList.Names[i];
    rec := Add(g, 'FLST', True);
    Add(rec, 'FormIDs', True);
    sFormID := HexFormID(rec);
    slFormList.ValueFromIndex[i] := sFormID;
    senv(rec, 'EDID', sEffect);
    DebugFormListMessage('  Assigning '+sFormID+' to '+sEffect);
  end;
end;

procedure ScanForSnow(e: IInterface; sl: TStringList);
begin
  if (genv(e, 'DATA\Flags') AND 8) = 8 then sl.Add(EditorID(e)+' has "Weather - Snowly" flag but isn''t included.');
end;

procedure ApplyEffect(f, e: IInterface; slMasters: TStringList);
var
  sEDID, sFormID, sEffect: String;
  rec: IInterface;
  i: Int;
  cFormID: Cardinal;
begin
  try
    sEDID := EditorID(e);
    DebugProcessMessage('      Found valid weather: '+sEDID);
    //First Add All Masters to List
    for i := 0 to Pred(MasterCount(f)) do begin
      AddMastersToList(MasterByIndex(f, i), slMasters);
    end;
    AddMastersToList(f, slMasters); //Dont forget the mainfile
    AddMastersToFile(iPatchFile,slMasters,true); //Add Masters to File
    rec := wbCopyElementToFile(e, iPatchFile, False, True); //Copy Element
    //Change records
    sEffect := slWeather.Values[sEDID];//Effect that needs to be applied
    sFormID := slEffect.Values[sEffect];//Get the Effect's FormID
    cFormID := StrToInt('$'+sFormID);//Convert into Cardinal
    senv(rec, 'NNAM', cFormID);//Apply Effect
    senv(rec, 'MNAM', 00000000); //NULL Precipitation
    if (slAppliedWeathers.IndexOfName(sEDID) = -1) AND IsMaster(e) then
      slAppliedWeathers.Add(geev(e, 'Record Header\FormID')+'='+sEffect);//Add Effect to list
  except 
    on x: exception do begin
      sScriptFailedReason := 'Something went wrong, I dont really know what... but take this:';
      AddMessage(x.Message);
      AddMessage(cDashes);
      CheckForErrors(0,e);
    end;
  end
end;

procedure ProcessWeathers;
var
  f, g, e: IInterface;
  iFileIdx, iElementIdx: Int;
  sEDID: String;
  slMasters, slNewWeather: TStringList;
begin
  DebugProcessMessage('Starting to process weathers');
  slMasters := TStringList.Create;
  slNewWeather := TStringList.Create;
  for iFileIdx := GetLoadOrder(iPatchFile) downto 0 do begin
    f := FileByIndex(iFileIdx);
    DebugProcessMessage('  Currently working on: '+GetFileName(f));
    g := GroupBySignature(f, 'WTHR');
    for iElementIdx := 0 to Pred(ElementCount(g)) do begin
      e := ElementByIndex(g,iElementIdx);
      sEDID := EditorID(e);
      DebugProcessMessage('    Looking at: '+sEDID);
      if slWeather.IndexOfName(sEDID) <> -1 then ApplyEffect(f, e, slMasters)
      else if doScan then ScanForSnow(e,slNewWeather);
    end;
  end;
  if doScan then AddMessage(slNewWeather.Text);//Print weathers that are not yet included.
  slMasters.Free;
  slNewWeather.Free;
end;

procedure FillFormIDList;
var
  sl: TStringList;
  i, j, iFormIdx: Integer;
  sEffect: String;
  e: IInterface;
begin
  DebugFormListMessage('Filling FormID Lists');
  for i := 0 to Pred(slEffect.Count) do begin
    sEffect := slEffect.Names[i];
    iFormIdx := slFormList.IndexOfName(sEffect+'_List');
    if iFormIdx = -1 then begin 
      sScriptFailedReason := 'Something went wrong with adding finding the idex of a FormID List';
      exit;
    end;
    DebugFormListMessage('  Reading Lists for '+ sEffect);
    sl := TStringList.Create;
    for j := 0 to Pred(slAppliedWeathers.Count) do begin
      if slAppliedWeathers.ValueFromIndex[j] = sEffect then begin
        sl.Add(slAppliedWeathers.Names[j]);
        DebugFormListMessage('    '+slAppliedWeathers.Names[j]);
      end;
    end;
    e := RecordByHexFormID(slFormList.ValueFromIndex[iFormIdx]);
    slev(e, 'FormIDs', sl);
    sl.Free;
  end;
end;

//
//Main Function
//=============================================================================================================
function Initialize: integer;
begin
  CreateStringLists;//Create StringLists
  InitialSetup; //Handles Intro and file checks
  if sScriptFailedReason <> '' then exit;
  {Do Work}
  LoadINI; //Ini Handling
  LoadEffects; //Loads the FormID in the slEffect list
  CreateFormIDLists;
  ProcessWeathers; //Applies the effects
  FillFormIDList;
end;

function Finalize: integer;
begin
  FreeStringLists;
  if sScriptFailedReason <> '' then begin
    AddMessage(sScriptFailedReason);
    Result := -1
  end
  else AddMessage('If you don''t see any errors then you are good to go.');
end;

end.
