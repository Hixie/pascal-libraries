{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit fileutils;

interface

uses
   baseunix;

type
   TFileData = record
      Start: Pointer;
      Length: size_t; // QWord, not Int64
      procedure Destroy();
   end;

function ReadFile(const FileName: AnsiString): TFileData; // This is efficient
function ReadTextFile(const FileName: AnsiString): UTF8String; // This is not

procedure WriteFile(const FileName: AnsiString; const FileData: TFileData);
procedure WriteTextFile(const FileName: AnsiString; const Data: UTF8String);

function IsEmptyDirectory(const Path: AnsiString): Boolean;

procedure DeleteDirectoryRecursively(const Path: AnsiString);

implementation

uses
   exceptions, sysutils;

function ReadFile(const FileName: AnsiString): TFileData;
var
   FileDescriptor: CInt;
   StatInfo: Stat;
   MapResult: Pointer;
begin
   FileDescriptor := fpOpen(FileName, O_RDONLY);
   if (FileDescriptor < 0) then
      raise EKernelError.Create(fpGetErrNo);
   if (fpFStat(FileDescriptor, StatInfo) <> 0) then // $DFA- for StatInfo
      raise EKernelError.Create(fpGetErrNo);
   MapResult := fpMMap(nil, StatInfo.st_size+1, PROT_READ, MAP_PRIVATE, FileDescriptor, 0); // $R-
   if (MapResult = MAP_FAILED) then
      raise EKernelError.Create(fpGetErrNo);
   fpClose(FileDescriptor);
   Result.Length := StatInfo.st_size; // $R-
   Result.Start := Pointer(MapResult);
end;

procedure TFileData.Destroy();
begin
  if (fpMUnMap(Self.Start, Self.Length) <> 0) Then
     raise EKernelError.Create(fpGetErrNo);
end;

function ReadTextFile(const FileName: AnsiString): UTF8String;
var
   Source: TFileData;
begin
   Source := ReadFile(FileName);
   if (Source.Length > High(Integer)) then
      raise Exception.Create('text file too big');
   SetLength(Result, Source.Length); // {BOGUS Hint: Function result variable of a managed type does not seem to be initialized}
   Move(Source.Start^, Result[1], Source.Length); // $R-
   Source.Destroy();
end;

procedure WriteFile(const FileName: AnsiString; const FileData: TFileData);
var
   FileDescriptor: CInt;
   Written: Int64;
   Buffer: PAnsiChar;
   Remaining, SegmentSize: size_t;
begin
   FileDescriptor := fpOpen(FileName, O_CREAT or O_TRUNC or O_WRONLY);
   if (FileDescriptor < 0) then
      raise EKernelError.Create(fpGetErrNo);
   try
      Buffer := FileData.Start;
      Remaining := FileData.Length;
      while (Remaining > 0) do
      begin
         SegmentSize := Remaining;
         if (SegmentSize > High(Written)) then
            SegmentSize := High(Written);
         Written := fpWrite(FileDescriptor, Buffer, SegmentSize);
         if (Written < 0) then
            raise EKernelError.Create(fpGetErrNo);
         if (Written <> SegmentSize) then
            raise Exception.Create('could not write entire file');
         Inc(Buffer, Written);
         Dec(Remaining, Written);
      end;
   finally
      fpClose(FileDescriptor);
   end;
end;

procedure WriteTextFile(const FileName: AnsiString; const Data: UTF8String);
var
   F: Text;
begin
   Assign(F, FileName);
   Rewrite(F);
   Write(F, Data);
   Close(F);
end;

function IsEmptyDirectory(const Path: AnsiString): Boolean;
var
   FileRecord: TSearchRec;
   GotOneDot, GotTwoDots, GotOther: Boolean;
begin
   if (DirectoryExists(Path)) then
   begin
      GotOneDot := False;
      GotTwoDots := False;
      GotOther := False;
      if (FindFirst(Path + '/*', faDirectory, FileRecord) = 0) then
         repeat
            if (FileRecord.Name = '.') then
               GotOneDot := True
            else
            if (FileRecord.Name = '..') then
               GotTwoDots := True
            else
            begin
               GotOther := True;
               break;
            end;
         until (FindNext(FileRecord) <> 0);
      Result := GotOneDot and GotTwoDots and not GotOther;
      FindClose(FileRecord);
   end
   else
      Result := False;
end;

procedure DeleteDirectoryRecursively(const Path: AnsiString);
var
   FileEntry: TRawbyteSearchRec;
begin
   Assert(Length(Path) > 1, 'Path is empty');
   Assert(Path[Length(Path)] = '/', 'Path does not end with a slash');
   if (FindFirst(Path + '*', faAnyFile, FileEntry) = 0) then
   begin
      repeat
         if ((FileEntry.Name = '.') or (FileEntry.Name = '..')) then
            continue;
         if ((FileEntry.Attr and faDirectory) > 0) then
         begin
            DeleteDirectoryRecursively(Path + FileEntry.Name + '/');
         end
         else
         begin
            DeleteFile(Path + FileEntry.Name);
         end;
      until FindNext(FileEntry) <> 0;
      FindClose(FileEntry);
   end;
   RemoveDir(Path);
end;

end.