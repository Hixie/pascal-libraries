{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit stringrecorder;

interface

type
   TStringRecorder = class abstract
    public
      procedure Add(const Value: UTF8String); virtual; abstract;
   end;

   TStringRecorderForStrings = class(TStringRecorder)
    private
     type
      PEntry = ^TEntry;
      TEntry = record
         Value: AnsiString;
         Next: PEntry;
      end;
     var
      FFirst, FLast: PEntry;
      FLength: Cardinal;
      function GetString(): UTF8String;
    public
      destructor Destroy(); override;
      procedure Add(const Value: UTF8String); override;
      property Value: UTF8String read GetString;
      property Length: Cardinal read FLength;
   end;

   TStringRecorderForFile = class abstract (TStringRecorder)
    private
      FFile: Text;
    public
      procedure Add(const Value: UTF8String); override;
   end;

   TStringRecorderForFileByFile = class(TStringRecorderForFile)
    public
      constructor Create(var AFile: Text);
   end;

   TStringRecorderForFileByName = class(TStringRecorderForFile)
    public
      constructor Create(const FileName: AnsiString);
      destructor Destroy(); override;
   end;

implementation

destructor TStringRecorderForStrings.Destroy();
var
   Next: PEntry;
begin
   while (Assigned(FFirst)) do
   begin
      Next := FFirst^.Next;
      Dispose(FFirst);
      FFirst := Next;
   end;
   inherited;
end;

procedure TStringRecorderForStrings.Add(const Value: UTF8String);
var
   Addition: PEntry;
begin
   New(Addition);
   Addition^.Value := Value;
   Addition^.Next := nil;
   if (not Assigned(FFirst)) then
   begin
      FFirst := Addition;
   end
   else
   begin
      FLast^.Next := Addition;
   end;
   FLast := Addition;
   Inc(FLength, system.Length(Value));
end;

function TStringRecorderForStrings.GetString(): UTF8String;
var
   Current: PEntry;
   Index: Cardinal;
begin
   SetLength(Result, FLength);
   Index := 1;
   Current := FFirst;
   while (Assigned(Current)) do
   begin
      Move(Current^.Value[1], Result[Index], system.Length(Current^.Value));
      Inc(Index, system.Length(Current^.Value));
      Current := Current^.Next;
   end;
end;


procedure TStringRecorderForFile.Add(const Value: UTF8String);
begin
   Write(FFile, Value);
end;


constructor TStringRecorderForFileByFile.Create(var AFile: Text);
begin
   FFile := AFile;
   inherited Create();
end;


constructor TStringRecorderForFileByName.Create(const FileName: AnsiString);
begin
   Assign(FFile, FileName);
   Rewrite(FFile);
   inherited Create();
end;

destructor TStringRecorderForFileByName.Destroy();
begin
   Close(FFile);
   inherited;
end;

end.
