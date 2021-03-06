// JCL_DEBUG_EXPERT_GENERATEJDBG ON
// JCL_DEBUG_EXPERT_INSERTJDBG ON
program BibleQuote;

{$R *.dres}

uses
  Forms,
  Classes,
  WideStrings,
  SysUtils,
  MainFrm in 'Forms\MainFrm.pas' {MainForm} ,
  InputFrm in 'Forms\InputFrm.pas' {InputForm} ,
  CopyrightFrm in 'Forms\CopyrightFrm.pas' {CopyrightForm} ,
  ConfigFrm in 'Forms\ConfigFrm.pas' {ConfigForm} ,
  ExceptionFrm in 'Forms\ExceptionFrm.pas' {ExceptionForm} ,
  AboutFrm in 'Forms\AboutFrm.pas' {AboutForm} ,
  PasswordDlg in 'Forms\PasswordDlg.pas' {PasswordBox} ,
  Containers in 'Collections\Containers.pas',
  Bible in 'Core\Bible.pas',
  BibleLinkParser in 'Core\BibleLinkParser.pas',
  BibleQuoteConfig in 'Core\BibleQuoteConfig.pas',
  BibleQuoteUtils in 'Core\BibleQuoteUtils.pas',
  CommandProcessor in 'Core\CommandProcessor.pas',
  Engine in 'Core\Engine.pas',
  EngineInterfaces in 'Core\EngineInterfaces.pas',
  AppInfo in 'Utils\AppInfo.pas',
  SystemInfo in 'Utils\SystemInfo.pas',
  GfxRenderers in 'UI\GfxRenderers.pas',
  HintTools in 'UI\HintTools.pas',
  HTMLViewerSite in 'UI\HTMLViewerSite.pas',
  WinUIServices in 'UI\WinUIServices.pas',
  ICommandProcessor in 'Core\ICommandProcessor.pas',
  VDTEditLink in 'UI\VDTEditLink.pas',
  Dict in 'Core\Dict.pas',
  SevenZipHelper in 'Utils\SevenZipHelper.pas',
  LinksParser in 'Core\LinksParser.pas',
  LinksParserIntf in 'Core\LinksParserIntf.pas',
  Favorites in 'Core\Favorites.pas',
  PlainUtils in 'Utils\PlainUtils.pas',
  StringProcs in 'Utils\StringProcs.pas',
  BackgroundServices in 'IO\BackgroundServices.pas',
  IOProcs in 'IO\IOProcs.pas',
  ModuleProcs in 'IO\ModuleProcs.pas',
  TagsDb in 'Data\TagsDb.pas' {TagsDbEngine: TDataModule} ,
  MultiLanguage in 'Core\MultiLanguage.pas',
  TabData in 'Core\TabData.pas',
  CRC32 in 'Utils\CRC32.pas',
  DockTabsFrm in 'Forms\DockTabsFrm.pas' {DockTabsForm} ,
  ThinCaptionedDockTree in 'UI\ThinCaptionedDockTree.pas',
  LayoutConfig in 'IO\LayoutConfig.pas',
  BookFra in 'Views\BookFra.pas' {BookFrame: TFrame} ,
  MemoFra in 'Views\MemoFra.pas' {MemoFrame: TFrame} ,
  FontManager in 'Core\FontManager.pas',
  LibraryFra in 'Views\LibraryFra.pas' {LibraryFrame: TFrame} ,
  ImageUtils in 'Utils\ImageUtils.pas',
  UITools in 'UI\UITools.pas',
  PopupFrm in 'Forms\PopupFrm.pas' {PopupForm} ,
  BookmarksFra in 'Views\BookmarksFra.pas' {BookmarksFrame: TFrame} ,
  BroadcastList in 'Collections\BroadcastList.pas',
  SearchFra in 'Views\SearchFra.pas' {SearchFrame: TFrame} ,
  TSKFra in 'Views\TSKFra.pas' {TSKFrame: TFrame} ,
  TagsVersesFra in 'Views\TagsVersesFra.pas' {TagsVersesFrame: TFrame} ,
  DictionaryFra in 'Views\DictionaryFra.pas' {DictionaryFrame: TFrame} ,
  NotifyMessages in 'Core\NotifyMessages.pas',
  StrongFra in 'Views\StrongFra.pas' {StrongFrame: TFrame} ,
  AppPaths in 'IO\AppPaths.pas',
  AppIni in 'IO\AppIni.pas';

{$R *.res}

var
  fn: string;
  param: string;

begin
  try
    if ParamStartedWith('/debug', param) then
    begin
      fn := ExtractFilePath(Application.Exename) + 'dbg.log';
      G_DebugEx := 1;
    end
    else
    begin
      fn := 'nul';
      G_DebugEx := 0;
    end;
    Assign(Output, fn);
    Rewrite(Output);
    writeln(NowDateTimeString(), 'BibleQuote dbg log started');
    Flush(Output);
    if ParamStartedWith('/memcheck', param) then
    begin
      ReportMemoryLeaksOnShutdown := true;
    end
    else
      ReportMemoryLeaksOnShutdown := false;
  except
  end;

  Application.Initialize;
  if not Assigned(TagsDbEngine) then
    TagsDbEngine := TTagsDbEngine.Create(Application);

  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TAboutForm, AboutForm);
  Application.CreateForm(TPasswordBox, PasswordBox);
  Application.CreateForm(TInputForm, InputForm);
  Application.CreateForm(TConfigForm, ConfigForm);

  Application.Run;
  try
    Close(Output);
  except
  end;

end.
