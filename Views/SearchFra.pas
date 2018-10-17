﻿unit SearchFra;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, TabData, BibleQuoteUtils,
  HTMLEmbedInterfaces, Htmlview, Vcl.StdCtrls, Vcl.ExtCtrls, Bible,
  StringProcs, LinksParser, MainFrm, LibraryFra, LayoutConfig, IOUtils,
  System.ImageList, Vcl.ImgList, LinksParserIntf, HintTools;

type
  TSearchFrame = class(TFrame, ISearchView, IBookSearchCallback)
    pnlSearch: TPanel;
    lblSearch: TLabel;
    cbSearch: TComboBox;
    cbList: TComboBox;
    btnFind: TButton;
    chkAll: TCheckBox;
    chkPhrase: TCheckBox;
    chkParts: TCheckBox;
    chkCase: TCheckBox;
    chkExactPhrase: TCheckBox;
    cbQty: TComboBox;
    btnSearchOptions: TButton;
    bwrSearch: THTMLViewer;
    btnBookSelect: TButton;
    lblBook: TLabel;
    imgList: TImageList;
    procedure bwrSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure bwrSearchKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure bwrSearchHotSpotClick(Sender: TObject; const SRC: string; var Handled: Boolean);
    procedure bwrSearchHotSpotCovered(Sender: TObject; const SRC: string);
    procedure btnFindClick(Sender: TObject);
    procedure cbSearchKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure cbListDropDown(Sender: TObject);
    procedure chkExactPhraseClick(Sender: TObject);
    procedure btnSearchOptionsClick(Sender: TObject);
    procedure cbQtyChange(Sender: TObject);
    procedure btnBookSelectClick(Sender: TObject);
  private
    mMainView: TMainForm;
    mTabsView: ITabsView;

    SearchPageSize: integer;
    IsSearching: Boolean;
    SearchResults: TStrings;
    SearchWords: TStrings;
    SearchTime: int64;
    SearchPage: integer; // what page we are in
    SearchBrowserPosition: Longint; // list search results pages...

    mblSearchBooksDDAltered: Boolean;
    mslSearchBooksCache: TStringList;

    mCurrentBook: TBible;
    mBookSelectView: TLibraryFrame;
    mBookSelectForm: TForm;

    LastSearchResultsPage: integer; // to show/hide page results (Ctrl-F3)

    procedure SearchListInit;
    procedure BookSearchComplete(bible: TBible);
    procedure OnBookSelectFormDeactivate(Sender: TObject);
    procedure OnBookSelect(Sender: TObject; modEntry: TModuleEntry);
  public
    constructor Create(AOwner: TComponent; mainView: TMainForm; tabsView: ITabsView); reintroduce;
    destructor Destroy; override;

    procedure DisplaySearchResults(page: integer);
    procedure Translate();

    procedure SetCurrentBook(shortPath: string);
    procedure OnVerseFound(bible: TBible; NumVersesFound, book, chapter, verse: integer; s: string; removeStrongs: boolean);
    procedure OnSearchComplete(bible: TBible);
  end;

implementation

{$R *.dfm}

constructor TSearchFrame.Create(AOwner: TComponent; mainView: TMainForm; tabsView: ITabsView);
begin
  inherited Create(AOwner);
  mMainView := mainView;
  mTabsView := tabsView;

  SearchResults := TStringList.Create;
  SearchWords := TStringList.Create;
  LastSearchResultsPage := 1;

  IsSearching := false;
  mslSearchBooksCache := TStringList.Create();
  mslSearchBooksCache.Duplicates := dupIgnore;

  mBookSelectForm := TForm.Create(self);
  mBookSelectForm.OnDeactivate := OnBookSelectFormDeactivate;

  mBookSelectView := TLibraryFrame.Create(nil);
  mBookSelectView.OnSelectModule := OnBookSelect;
  mBookSelectView.cmbBookType.Enabled := true;
  mBookSelectView.cmbBookType.ItemIndex := 0;
  mBookSelectView.Align := TAlign.alClient;
  mBookSelectView.Parent := mBookSelectForm;

  with bwrSearch do
  begin
    DefFontName := MainCfgIni.SayDefault('RefFontName', 'Microsoft Sans Serif');
    DefFontSize := StrToInt(MainCfgIni.SayDefault('RefFontSize', '12'));
    DefFontColor := Hex2Color(MainCfgIni.SayDefault('RefFontColor', Color2Hex(clWindowText)));

    DefBackGround := Hex2Color(MainCfgIni.SayDefault('DefBackground', Color2Hex(clWindow))); // '#EBE8E2'
    DefHotSpotColor := Hex2Color(MainCfgIni.SayDefault('DefHotSpotColor', Color2Hex(clHotLight))); // '#0000FF'
  end;
end;

procedure TSearchFrame.OnBookSelectFormDeactivate(Sender: TObject);
begin
  LibFormWidth := mBookSelectForm.Width;
  LibFormHeight := mBookSelectForm.Height;
  LibFormTop := mBookSelectForm.Top;
  LibFormLeft := mBookSelectForm.Left;
end;

procedure TSearchFrame.OnBookSelect(Sender: TObject; modEntry: TModuleEntry);
begin
  SetCurrentBook(modEntry.mShortPath);

  PostMessage(mBookSelectForm.Handle, wm_close, 0, 0);
end;

destructor TSearchFrame.Destroy();
begin
  if Assigned(SearchResults) then
    FreeAndNil(SearchResults);

  if Assigned(SearchWords) then
    FreeAndNil(SearchWords);

  if Assigned(mslSearchBooksCache) then
    FreeAndNil(mslSearchBooksCache);

  inherited;
end;

procedure TSearchFrame.btnBookSelectClick(Sender: TObject);
begin
  mBookSelectView.SetModules(mMainView.mModules);

  mBookSelectForm.Width := LibFormWidth;
  mBookSelectForm.Height := LibFormHeight;
  mBookSelectForm.Top := LibFormTop;
  mBookSelectForm.Left := LibFormLeft;

  mBookSelectForm.ShowModal();
end;

procedure TSearchFrame.btnFindClick(Sender: TObject);
var
  s: set of 0 .. 255;
  searchText, wrd, wrdnew, books: string;
  params: byte;
  lnks: TStringList;
  book, chapter, v1, v2, linksCnt, i: integer;

  function metabook(const bible: TBible; const str: string): Boolean;
  var
    wl: string;
  label success;
  begin
    wl := LowerCase(str);
    if (Pos('нз', wl) = 1) or (Pos('nt', wl) = 1) then
    begin

      if bible.Trait[bqmtNewCovenant] and bible.InternalToReference(40, 1, 1, book, chapter, v1) then
      begin
        s := s + [39 .. 65];
      end;
      goto success;
    end
    else if (Pos('вз', wl) = 1) or (Pos('ot', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] and bible.InternalToReference(1, 1, 1, book, chapter, v1) then
      begin
        s := s + [0 .. 38];
      end;
      goto success;
    end
    else if (Pos('пят', wl) = 1) or (Pos('pent', wl) = 1) or
      (Pos('тор', wl) = 1) or (Pos('tor', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] and bible.InternalToReference(1, 1, 1, book, chapter, v1) then
      begin
        s := s + [0 .. 4];
      end;
      goto success;
    end
    else if (Pos('ист', wl) = 1) or (Pos('hist', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] then
      begin
        s := s + [0 .. 15];
      end;
      goto success;
    end
    else if (Pos('уч', wl) = 1) or (Pos('teach', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] then
      begin
        s := s + [16 .. 21];
      end;
      goto success;
    end
    else if (Pos('бпрор', wl) = 1) or (Pos('bproph', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] then
      begin
        s := s + [22 .. 26];
      end;
      goto success;
    end
    else if (Pos('мпрор', wl) = 1) or (Pos('mproph', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] then
      begin
        s := s + [27 .. 38];
      end;
      goto success;
    end
    else if (Pos('прор', wl) = 1) or (Pos('proph', wl) = 1) then
    begin
      if bible.Trait[bqmtOldCovenant] then
      begin
        s := s + [22 .. 38];
        if bible.Trait[bqmtNewCovenant] and bible.InternalToReference(66, 1, 1, book, chapter, v1) then
        begin
          Include(s, 65);
        end;
        goto success;
      end
    end
    else if (Pos('ева', wl) = 1) or (Pos('gos', wl) = 1) then
    begin
      if bible.Trait[bqmtNewCovenant] then
      begin
        s := s + [39 .. 42];
      end;
      goto success;
    end
    else if (Pos('пав', wl) = 1) or (Pos('paul', wl) = 1) then
    begin
      if bible.Trait[bqmtNewCovenant] and bible.InternalToReference(52, 1, 1, book, chapter, v1) then
      begin
        s := s + [book - 1 .. book + 12];
      end;
      goto success;
    end;

    Result := false;
    Exit;
  success:
    Result := true;
  end;

begin
  if not Assigned(mCurrentBook) then
    Exit;

  if cbQty.ItemIndex < cbQty.Items.Count - 1 then
    SearchPageSize := StrToInt(cbQty.Items[cbQty.ItemIndex])
  else
    SearchPageSize := 50000;

  if IsSearching then
  begin
    IsSearching := false;
    mCurrentBook.StopSearching;
    Screen.Cursor := crDefault;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    IsSearching := true;

    s := [];

    if (not mCurrentBook.isBible)
    then
    begin
      if (cbList.ItemIndex <= 0) then
        s := [0 .. mCurrentBook.BookQty - 1]
      else
        s := [cbList.ItemIndex - 1];
    end
    else
    begin // FULL BIBLE SEARCH
      searchText := Trim(cbList.Text);
      linksCnt := cbList.Items.Count - 1;
      if not mblSearchBooksDDAltered then
        if (cbList.ItemIndex < 0) then
          for i := 0 to linksCnt do
            if CompareText(cbList.Items[i], searchText) = 0 then
            begin
              cbList.ItemIndex := i;
              break;
            end;

      if (cbList.ItemIndex < 0) or (mblSearchBooksDDAltered) then
      begin
        lnks := TStringList.Create;
        try
          books := '';
          StrToLinks(searchText, lnks);
          linksCnt := lnks.Count - 1;
          for i := 0 to linksCnt do
          begin
            if metabook(mCurrentBook, lnks[i]) then
            begin

              books := books + FirstWord(lnks[i]) + ' ';
              continue
            end
            else if mCurrentBook.OpenReference(lnks[i], book, chapter, v1, v2) and
              (book > 0) and (book < 77) then
            begin
              Include(s, book - 1);
              if Pos(mCurrentBook.ShortNames[book], books) <= 0 then
              begin

                books := books + mCurrentBook.ShortNames[book] + ' ';
              end;

            end;

          end;
          books := Trim(books);
          if (Length(books) > 0) and (mslSearchBooksCache.IndexOf(books) < 0) then
            mslSearchBooksCache.Add(books);

        finally
          lnks.Free();
        end;
      end
      else
        case integer(cbList.Items.Objects[cbList.ItemIndex]) of
          0:
            s := [0 .. 65];
          -1:
            s := [0 .. 38];
          -2:
            s := [39 .. 65];
          -3:
            s := [0 .. 4];
          -4:
            s := [5 .. 21];
          -5:
            s := [22 .. 38];
          -6:
            s := [39 .. 43];
          -7:
            s := [44 .. 65];
          -8:
            begin
              if mCurrentBook.Trait[bqmtApocrypha] then
                s := [66 .. mCurrentBook.BookQty - 1]
              else
                s := [0];
            end;
        else
          s := [cbList.ItemIndex - 8 - ord(mCurrentBook.Trait[bqmtApocrypha])];
          // search in single book
        end;
    end;

    searchText := Trim(cbSearch.Text);
    StrReplace(searchText, '.', ' ', true);
    StrReplace(searchText, ',', ' ', true);
    StrReplace(searchText, ';', ' ', true);
    StrReplace(searchText, '?', ' ', true);
    StrReplace(searchText, '"', ' ', true);
    searchText := Trim(searchText);

    if searchText <> '' then
    begin
      if cbSearch.Items.IndexOf(searchText) < 0 then
        cbSearch.Items.Insert(0, searchText);

      SearchResults.Clear;

      SearchWords.Clear;
      wrd := cbSearch.Text;

      if not chkExactPhrase.Checked then
      begin
        while wrd <> '' do
        begin
          wrdnew := DeleteFirstWord(wrd);

          SearchWords.Add(wrdnew);
        end;
      end
      else
      begin
        wrdnew := Trim(wrd);
        SearchWords.Add(wrdnew);
      end;

      params :=
        spWordParts * (1 - ord(chkParts.Checked)) +
        spContainAll * (1 - ord(chkAll.Checked)) +
        spFreeOrder * (1 - ord(chkPhrase.Checked)) +
        spAnyCase * (1 - ord(chkCase.Checked)) +
        spExactPhrase * ord(chkExactPhrase.Checked);

      if (params and spExactPhrase = spExactPhrase) and (params and spWordParts = spWordParts) then
        params := params - spWordParts;

      SearchTime := GetTickCount;

      // TODO: fix search with strongs, currently false
      mCurrentBook.Search(searchText, params, s, false, Self);
      //mCurrentBook.Search(searchText, params, s, not (vtisShowStrongs in bookView.BookTabInfo.State), Self);
    end;
  finally
    Screen.Cursor := crDefault;
  end
end;

procedure TSearchFrame.BookSearchComplete(bible: TBible);
begin
  IsSearching := false;
  SearchTime := GetTickCount - SearchTime;
  lblSearch.Caption := lblSearch.Caption + ' (' + IntToStr(SearchTime) + ')';
  DisplaySearchResults(1);
end;

procedure TSearchFrame.btnSearchOptionsClick(Sender: TObject);
begin
  if pnlSearch.Height > chkCase.Top + chkCase.Height then
  begin // wrap it
    pnlSearch.Height := chkAll.Top;
    btnSearchOptions.Caption := '>';
  end
  else
  begin
    pnlSearch.Height := lblSearch.Top + lblSearch.Height + 10;
    btnSearchOptions.Caption := '<';
  end;

  cbSearch.SetFocus;
end;

procedure TSearchFrame.bwrSearchHotSpotClick(Sender: TObject; const SRC: string; var Handled: Boolean);
var
  i, code: integer;
  book, chapter, fromverse, toverse: integer;
  command: string;
begin
  if not Assigned(mCurrentBook) then
    Exit;

  command := SRC;
  Val(command, i, code);
  if code = 0 then
    DisplaySearchResults(i)
  else
  begin
    if (Copy(command, 1, 3) <> 'go ') then
    begin
      if mCurrentBook.OpenReference(command, book, chapter, fromverse, toverse) then
        command := Format('go %s %d %d %d %d', [mCurrentBook.ShortPath, book, chapter, fromverse, toverse])
      else
        command := '';
    end;

    if Length(command) > 0 then
      mMainView.OpenOrCreateBookTab(command, '', mMainView.DefaultBookTabState);
  end;
  Handled := true;
end;

procedure TSearchFrame.bwrSearchHotSpotCovered(Sender: TObject; const SRC: string);
begin
  // TODO: decide what source to use for hints
  // show hints from this source
end;

procedure TSearchFrame.bwrSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  SearchBrowserPosition := bwrSearch.Position;
end;

procedure TSearchFrame.bwrSearchKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_NEXT) and (bwrSearch.Position = SearchBrowserPosition) then
    DisplaySearchResults(SearchPage + 1);

  if (Key = VK_PRIOR) and (bwrSearch.Position = SearchBrowserPosition) then
  begin
    if SearchPage = 1 then
      Exit;
    DisplaySearchResults(SearchPage - 1);
    bwrSearch.PositionTo('endofsearchresults');
  end;
end;

procedure TSearchFrame.cbListDropDown(Sender: TObject);
begin
  if not Assigned(mCurrentBook) then
    Exit;

  if IsDown(VK_MENU) and (mCurrentBook.isBible) and (mslSearchBooksCache.Count > 0)
  then
  begin
    cbList.Items.Assign(mslSearchBooksCache);
    mblSearchBooksDDAltered := true;
  end
  else
  begin
    if mblSearchBooksDDAltered then
      SearchListInit();
    mblSearchBooksDDAltered := false;
  end;
end;

procedure TSearchFrame.cbQtyChange(Sender: TObject);
begin
  if cbQty.ItemIndex < cbQty.Items.Count - 1 then
    SearchPageSize := StrToInt(cbQty.Items[cbQty.ItemIndex])
  else
    SearchPageSize := 50000;
  DisplaySearchResults(1);
end;

procedure TSearchFrame.cbSearchKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  s: TComboBox;
begin
  if Key = VK_RETURN then
  begin
    s := (Sender as TComboBox);
    if s.DroppedDown then
      s.DroppedDown := false;
  end;
end;

procedure TSearchFrame.chkExactPhraseClick(Sender: TObject);
begin
  if chkExactPhrase.Checked then
  begin
    chkAll.Checked := false;
    chkPhrase.Checked := false;
    chkParts.Checked := false;
    chkCase.Checked := false;
  end;
end;

procedure TSearchFrame.Translate();
begin
  Lang.TranslateControl(self, 'DockTabsForm');

  if not Assigned(mCurrentBook) then
    lblBook.Caption := Lang.SayDefault('SelectBook', 'Select book');

  cbList.ItemIndex := 0;
  mBookSelectView.Translate();

  mBookSelectForm.Caption := Lang.SayDefault('SelectBook', 'Select book');
end;

procedure TSearchFrame.SetCurrentBook(shortPath: string);
var
  iniPath: string;
  caption: string;
begin
  mCurrentBook := TBible.Create(mMainView);

  iniPath := TPath.Combine(shortPath, 'bibleqt.ini');
  mCurrentBook.inifile := MainFileExists(iniPath);
  SearchListInit;

  if (mCurrentBook.isBible) then
    cbList.Style := csDropDownList
  else
    cbList.Style := csDropDown;

  caption := Format('%s, %s', [mCurrentBook.Name, mCurrentBook.ShortName]);
  lblBook.Caption := caption.Trim([',', ' ']);
end;

procedure TSearchFrame.DisplaySearchResults(page: integer);
var
  i, limit: integer;
  s: string;
  dSource: string;
begin
  if not Assigned(mCurrentBook) then
    Exit;

  if (SearchPageSize * (page - 1) > SearchResults.Count) or (SearchResults.Count = 0) then
  begin
    Screen.Cursor := crDefault;
    Exit;
  end;

  SearchPage := page;

  dSource := Format('<b>"<font face="%s">%s</font>"</b> (%d) <p>', [mCurrentBook.fontName, cbSearch.Text, SearchResults.Count]);

  limit := SearchResults.Count div SearchPageSize + 1;
  if SearchPageSize * (limit - 1) = SearchResults.Count then
    limit := limit - 1;

  s := '';
  for i := 1 to limit - 1 do
  begin
    if i <> page then
      s := s + Format('<a href="%d">%d-%d</a> ', [i, SearchPageSize * (i - 1) + 1, SearchPageSize * i])
    else
      s := s + Format('%d-%d ', [SearchPageSize * (i - 1) + 1, SearchPageSize * i]);
  end;

  if limit <> page then
    s := s + Format('<a href="%d">%d-%d</a> ',
      [limit, SearchPageSize * (limit - 1) + 1, SearchResults.Count])
  else
    s := s + Format('%d-%d ', [SearchPageSize * (limit - 1) + 1, SearchResults.Count]);

  limit := SearchPageSize * page - 1;
  if limit >= SearchResults.Count then
    limit := SearchResults.Count - 1;

  for i := SearchPageSize * (page - 1) to limit do
    AddLine(dSource, '<font size=-1>' + IntToStr(i + 1) + '.</font> ' + SearchResults[i]);

  AddLine(dSource, '<a name="endofsearchresults"><p>' + s + '<br><p>');

  bwrSearch.CharSet := mTabsView.Browser.CharSet;

  StrReplace(dSource, '<*>', '<font color=' + mMainView.SelTextColor + '>', true);
  StrReplace(dSource, '</*>', '</font>', true);

  bwrSearch.LoadFromString(dSource);

  LastSearchResultsPage := page;
  Screen.Cursor := crDefault;

  try
    bwrSearch.SetFocus;
  except
    // do nothing
  end;

end;

procedure TSearchFrame.OnVerseFound(bible: TBible; NumVersesFound, book, chapter, verse: integer; s: string; removeStrongs: boolean);
var
  i: integer;
begin
  if not Assigned(bible) then
    Exit;

  lblSearch.Caption := Format('[%d] %s', [NumVersesFound, bible.FullNames[book]]);

  if s <> '' then
  begin
    s := ParseHTML(s, '');

    if bible.Trait[bqmtStrongs] and (removeStrongs = true) then
      s := DeleteStrongNumbers(s);

    StrDeleteFirstNumber(s);

    // color search result!!!
    for i := 0 to SearchWords.Count - 1 do
      StrColorUp(s, SearchWords[i], '<*>', '</*>', chkCase.Checked);

    SearchResults.Add(
      Format('<a href="go %s %d %d %d 0">%s</a> <font face="%s">%s</font><br>',
      [bible.ShortPath, book, chapter, verse,
      bible.ShortPassageSignature(book, chapter, verse, verse),
      bible.fontName, s]));
  end;

  Application.ProcessMessages;
end;

procedure TSearchFrame.OnSearchComplete(bible: TBible);
begin
  BookSearchComplete(bible);
end;

procedure TSearchFrame.SearchListInit;
var
  i: integer;
begin
  if not Assigned(mCurrentBook) then
    Exit;

  if (not mCurrentBook.isBible) then
    with cbList do
    begin
      Items.BeginUpdate;
      Items.Clear;

      Items.AddObject(Lang.Say('SearchAllBooks'), TObject(0));

      for i := 1 to mCurrentBook.BookQty do
        Items.AddObject(mCurrentBook.FullNames[i], TObject(i));

      Items.EndUpdate;
      ItemIndex := 0;
      Exit;
    end;

  with cbList do
  begin
    Items.BeginUpdate;
    Items.Clear;

    Items.AddObject(Lang.Say('SearchWholeBible'), TObject(0));
    if mCurrentBook.Trait[bqmtOldCovenant] and mCurrentBook.Trait[bqmtNewCovenant] then
      Items.AddObject(Lang.Say('SearchOT'), TObject(-1)); // Old Testament
    if mCurrentBook.Trait[bqmtNewCovenant] and mCurrentBook.Trait[bqmtNewCovenant] then
      Items.AddObject(Lang.Say('SearchNT'), TObject(-2)); // New Testament
    if mCurrentBook.Trait[bqmtOldCovenant] then
      Items.AddObject(Lang.Say('SearchPT'), TObject(-3)); // Pentateuch
    if mCurrentBook.Trait[bqmtOldCovenant] then
      Items.AddObject(Lang.Say('SearchHP'), TObject(-4));
    // Historical and Poetical
    if mCurrentBook.Trait[bqmtOldCovenant] then
      Items.AddObject(Lang.Say('SearchPR'), TObject(-5)); // Prophets
    if mCurrentBook.Trait[bqmtNewCovenant] then
      Items.AddObject(Lang.Say('SearchGA'), TObject(-6)); // Gospels and Acts
    if mCurrentBook.Trait[bqmtNewCovenant] then
      Items.AddObject(Lang.Say('SearchER'), TObject(-7)); // Epistles and Revelation
    if mCurrentBook.Trait[bqmtApocrypha] then
      Items.AddObject(Lang.Say('SearchAP'), TObject(-8)); // Apocrypha

    for i := 1 to mCurrentBook.BookQty do
      Items.AddObject(mCurrentBook.FullNames[i], TObject(i));

    Items.EndUpdate;
    ItemIndex := 0;
  end;
end;

end.