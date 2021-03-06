unit BackgroundServices;

interface

uses
  Classes, SyncObjs, SysUtils, Dict, Windows, BibleQuoteUtils, EngineInterfaces,
  TagsDb, Types, IOUtils, AppPaths;

type

  TbqWorkerRequiredOperation = (
    wroSleep,
    wroTerminated,
    wroLoadDictionaries,
    wroInitDicTokens,
    wroInitVerseListEngine);

  TbqWorker = class(TThread)

  protected
    mSection: TCriticalSection;
    mEvent, mDoneOperationEvent: TSimpleEvent;
    mDictionariesPath: string;
    mDictionaryTokens: TBQStringList;
    mOperation: TbqWorkerRequiredOperation;

    mBusy: boolean;
    mEngine: IInterface;
    mResult: HRESULT;
    procedure Execute; override;
    function _LoadDictionaries(const path: string): HRESULT;
    function getAsynInface(): IbqEngineAsyncTraits;
    function _InitDictionaryItemsList(lst: TBQStringList): HRESULT;
    function _InitVerseListEngine(): HRESULT;
    function GetBusy(): boolean;
    procedure SetBusy(aVal: boolean);

  public
    function LoadDictionaries(const fromPath: string; foreground: boolean): HRESULT;
    function InitDictionaryItemsList(lst: TBQStringList; foreground: boolean = false): HRESULT;
    function InitVerseListEngine(foreground: boolean): HRESULT;
    function WaitUntilDone(dwTime: DWORD): TWaitResult;
    constructor Create(iEngine: IInterface);
    procedure Finalize();
    destructor Destroy; override;
    procedure Resume();
    procedure Suspend();
    property OperationResult: HRESULT read mResult;
    property Busy: boolean read GetBusy write SetBusy;
  end;

implementation

{ Important: Methods and properties of objects in visual components can only be
  used in a method called using Synchronize, for example,

  Synchronize(UpdateCaption);

  and UpdateCaption could look like,

  procedure TbqWorker.UpdateCaption;
  begin
  Form1.Caption := 'Updated in a thread';
  end; }

{$IFDEF MSWINDOWS}

type
  TThreadNameInfo = record
    FType: LongWord; // must be 0x1000
    FName: PChar; // pointer to name (in user address space)
    FThreadID: LongWord; // thread ID (-1 indicates caller thread)
    FFlags: LongWord; // reserved for future use, must be zero
  end;
{$ENDIF}
  { TbqWorker }

procedure TbqWorker.SetBusy(aVal: boolean);
begin
  try
    mSection.Acquire();
    mBusy := aVal;
  finally
    mSection.Release()
  end;

end;

procedure TbqWorker.Suspend;
begin
  TThread(self).Suspend();
end;

function TbqWorker.WaitUntilDone(dwTime: DWORD): TWaitResult;
begin
  result := mDoneOperationEvent.WaitFor(dwTime);
end;

function TbqWorker._InitDictionaryItemsList(lst: TBQStringList): HRESULT;
var
  dicCount, wordCount, dicIx, wordIx: integer;
  hr: HRESULT;
  engine: IbqEngineDicTraits;
  currentDic: TDict;
begin
  result := S_FALSE;
  hr := mEngine.QueryInterface(IbqEngineDicTraits, engine);
  if hr <> S_OK then
    exit;

  if lst = nil then
    lst := TBQStringList.Create
  else
    lst.Clear();
  lst.Sorted := true;
  dicCount := engine.DictionariesCount() - 1;
  for dicIx := 0 to dicCount do
  begin
    currentDic := engine.GetDictionary(dicIx);
    wordCount := currentDic.Words.Count - 1;
    for wordIx := 0 to wordCount do
    begin
      lst.Add(currentDic.Words[wordIx]);
    end;
  end;
  result := S_OK;
end;

function TbqWorker._InitVerseListEngine(): HRESULT;
begin
  try
    TagsDbEngine.InitVerseListEngine(TPath.Combine(TAppDirectories.UserSettings, 'TagsDb.bqd'));
    result := S_OK;
  except
    on e: Exception do
    begin
      result := -2;
    end;
  end;
end;

function TbqWorker._LoadDictionaries(const path: string): HRESULT;
var
  dirList: TStringDynArray;
  dictFileList: TStringDynArray;
  engine: IbqEngineDicTraits;
  hr: HRESULT;
  dictIdxFileName, dictHtmlFileName: string;
  dictionary: TDict;
  i, j: integer;
begin
  result := S_FALSE;
  hr := mEngine.QueryInterface(IbqEngineDicTraits, engine);
  if hr <> S_OK then
    exit;

  dirList := TDirectory.GetDirectories(path);
  for i := 0 to Length(dirList) - 1 do
  begin
    dictFileList := TDirectory.GetFiles(dirList[i], '*.idx');
    for j := 0 to Length(dictFileList) - 1 do
    begin
      dictIdxFileName := dictFileList[j];
      dictHtmlFileName := Copy(dictIdxFileName, 1, length(dictIdxFileName) - 3) + 'htm';

      dictionary := TDict.Create;
      dictionary.Initialize(dictIdxFileName, dictHtmlFileName);

      engine.AddDictionary(dictionary);

      result := S_OK;
    end;
  end;
end;

constructor TbqWorker.Create(iEngine: IInterface);
begin
  mEngine := iEngine;
  mSection := TCriticalSection.Create;
  mEvent := TSimpleEvent.Create(nil, false, false, '');
  mDoneOperationEvent := TSimpleEvent.Create(nil, false, false, '');
  inherited Create(false);
end;

destructor TbqWorker.Destroy;
begin
  Finalize();
  FreeAndNil(mSection);
  FreeAndNil(mEvent);
  FreeAndNil(mDoneOperationEvent);
  FreeAndNil(mDictionaryTokens);
  FreeAndNil(mSection);

  inherited;
end;

procedure TbqWorker.Execute;
var
  engine: IbqEngineAsyncTraits;
  wr: TWaitResult;
begin
  repeat
    wr := mEvent.WaitFor(INFINITE);
  until wr <> wrTimeout;
  if wr <> wrSignaled then
    exit;

  repeat
    mBusy := true;
    mDoneOperationEvent.ResetEvent();
    try
      if mOperation = wroLoadDictionaries then
      begin
        mResult := _LoadDictionaries(mDictionariesPath);
        engine := getAsynInface();
        if assigned(engine) then
          engine.AsyncStateCompleted(bqsDictionariesLoading, mResult);
        mDictionariesPath := '';
      end
      else if mOperation = wroInitDicTokens then
      begin
        mResult := _InitDictionaryItemsList(mDictionaryTokens);
        engine := getAsynInface();
        if assigned(engine) then
          engine.AsyncStateCompleted(bqsDictionariesListCreating, mResult);
        mDictionaryTokens := nil;
      end
      else if mOperation = wroInitVerseListEngine then
      begin
        mResult := _InitVerseListEngine();
        engine := getAsynInface();
        if assigned(engine) then
          engine.AsyncStateCompleted(bqsVerseListEngineInitializing, mResult);
      end;
      // SetName;
    except
      mResult := -2;
      MessageBeep(MB_ICONERROR);
    end;

    mOperation := wroSleep;
    Busy := false;
    mDoneOperationEvent.SetEvent();
    if not Terminated then
      repeat
        wr := mEvent.WaitFor(3000);
      until (wr <> wrTimeout) and (mOperation <> wroSleep) or (Terminated);

  until (Terminated) or (wr <> wrSignaled);

  mOperation := wroTerminated;

end;

procedure TbqWorker.Finalize;
begin
  Terminate();
  if mOperation = wroSleep then
  begin
    mOperation := wroTerminated;
    mEvent.SetEvent();
  end;
  WaitFor();
  mEngine := nil;
end;

function TbqWorker.getAsynInface(): IbqEngineAsyncTraits;
var
  hr: HRESULT;
begin
  if assigned(mEngine) then
    hr := mEngine.QueryInterface(IbqEngineAsyncTraits, result)
  else
    hr := S_FALSE;
  if hr <> S_OK then
    result := nil;
end;

function TbqWorker.GetBusy: boolean;
begin
  try
    mSection.Acquire();
    result := mBusy
  finally
    mSection.Release()
  end;
end;

function TbqWorker.InitDictionaryItemsList(lst: TBQStringList; foreground: boolean = false): HRESULT;
begin
  result := S_FALSE;
  if foreground then
  begin
    result := _InitDictionaryItemsList(lst);
    exit
  end;

  if Busy then
    exit;

  mOperation := wroInitDicTokens;
  mDictionaryTokens := lst;
  mEvent.SetEvent();
  result := S_OK;
end;

function TbqWorker.InitVerseListEngine(foreground: boolean): HRESULT;
begin
  if foreground then
  begin
    result := _InitVerseListEngine();
    exit
  end;
  result := S_FALSE;
  if Busy then
    exit;
  mOperation := wroInitVerseListEngine;
  mEvent.SetEvent();
  result := S_OK;
end;

function TbqWorker.LoadDictionaries(const fromPath: string; foreground: boolean): HRESULT;
begin
  result := S_FALSE;
  if foreground then
  begin
    result := _LoadDictionaries(fromPath);

    exit;
  end;

  if (Busy) then
    exit;

  mOperation := wroLoadDictionaries;
  mDictionariesPath := fromPath;
  mEvent.SetEvent();
  result := S_OK;
end;

procedure TbqWorker.Resume;
begin
  Busy := true;
  if Suspended then
    TThread(self).Resume();

end;

end.
