{$MODE OBJFPC} { -*- delphi -*- }
{$FATAL this is not checked in}
{$INCLUDE settings.inc}
unit stringstream;

// This is for reading null-separated UTF-8-encoded data consisting of
// just integers, floating-point numbers, booleans, or strings.

interface

type
   TStringStreamReader = class
    // this class can never fail. invalid input will just start returning empty strings and 0s.
    private
      FInput: UTF8String;
      FPosition: Cardinal; // last character to have been read
      FEnded: Boolean;
      function ReadUntilNull(const Terminal: Char = #0): UTF8String;
      procedure Close();
    public
      constructor Create(const Input: UTF8String);
      function ReadCardinal(): Cardinal;
      function ReadDouble(): Double;
      function ReadString(): UTF8String;
      function ReadString(const MaxLength: Cardinal): UTF8String;
      function ReadBoolean(): Boolean;
      procedure ReadEnd();
      procedure Bail(); // call this when you can't be bothered to check if the rest of the data is valid and you just want to stop reading
      property Ended: Boolean read FEnded;
   end;

   TStringStreamWriter = class
    private
      FValue: UTF8String;
      {$IFOPT C+} FClosed: Boolean; {$ENDIF}
    protected
      procedure ProcessValue(const Value: UTF8String); virtual; abstract;
    public
      constructor Create();
      {$IFOPT C+} destructor Destroy(); override; {$ENDIF}
      procedure WriteCardinal(const Value: Cardinal);
      procedure WriteDouble(const Value: Double);
      procedure WriteString(const Value: UTF8String);
      procedure WriteBoolean(const Value: Boolean);
      procedure Close();
   end;

   {$IFDEF DEBUG}
   TStringStreamWriterDebug = class(TStringStreamWriter)
    private
      FExpectation: UTF8String;
      FSuccess: Boolean;
    protected
      procedure ProcessValue(const Value: UTF8String); override;
    public
      constructor Create(Expectation: UTF8String);
      property Success: Boolean read FSuccess;
   end;
   {$ENDIF}

implementation

uses
   sysutils, stringutils, exceptions;

constructor TStringStreamReader.Create(const Input: UTF8String);
begin
   FInput := Input;
end;

function TStringStreamReader.ReadUntilNull(const Terminal: Char): UTF8String;
var
   Start: Cardinal;
begin
   Start := FPosition+1;
   repeat
      Inc(FPosition);
      if (FPosition > Length(FInput)) then
      begin
         Result := '';
         Close();
         Exit;
      end;
   until (FInput[FPosition] = Terminal);
   Result := Copy(FInput, Start, FPosition - Start);
end;

procedure TStringStreamReader.Close();
begin
   FPosition := Length(FInput)+1; // move pointer to past the end
end;

function TStringStreamReader.ReadCardinal(): Cardinal;
var
   Value: Integer;
begin
   Value := StrToIntDef(ReadUntilNull(), 0);
   if (Value < 0) then
      Value := 0;
   Result := Value;
end;

function TStringStreamReader.ReadDouble(): Double;
begin
   Result := XXX;
end;

{ // this implements a size-prefixed field
function TStringStreamReader.ReadByteString(): UTF8String;
var
   ExpectedLength: Cardinal;
begin
   ExpectedLength := ReadCardinal();
   if (Length(FInput) - FPosition < ExpectedLength) then
   begin
      Result := '';
      Close();
   end;
   Result := Copy(FInput, FPosition+1, ExpectedLength);
   Inc(FPosition, ExpectedLength);
end;
}

function TStringStreamReader.ReadString(): UTF8String;
begin
   Result := ReadUntilNull();
   if (not IsValidUTF8(Result)) then
   begin
      Result := '';
      Close();
   end;
end;

function TStringStreamReader.ReadString(const MaxLength: Cardinal): UTF8String;
begin
   Result := ReadString();
   if (Length(Result) > MaxLength) then
   begin
      Result := '';
      Close();
   end;
end;

function TStringStreamReader.ReadBoolean(): Boolean;
var
   Buffer: UTF8String;
begin
   Buffer := ReadUntilNull();
   if (Buffer = 'T') then
   begin
      Result := True;
   end
   else
   if (Buffer = 'F') then
   begin
      Result := False;
   end
   else
   begin
      Result := False;
      Close();
   end;
end;

procedure TStringStreamReader.ReadEnd();
begin
   if (FPosition = Length(FInput)) then // pointer just reached past the end of the input string
      FEnded := True;
   Close();
end;

procedure TStringStreamReader.Bail();
begin
   FEnded := True;
   Close();
end;


constructor TStringStreamWriter.Create();
begin
end;

procedure TStringStreamWriter.WriteCardinal(const Value: Cardinal);
begin
   FValue := FValue + IntToStr(Value) + #0;
end;

procedure TStringStreamWriter.WriteDouble(const Value: Double);
begin
   FValue := FValue + FloatToStrF(Value, ffExponent, 15, 0) + #0;
end;

{ // this implements a size-prefixed field
procedure TStringStreamWriter.WriteByteString(const Value: UTF8String);
begin
   FValue := FValue + IntToStr(Length(Value)) + #0 + Value;
end;
}

procedure TStringStreamWriter.WriteString(const Value: UTF8String);
begin
   Assert(IsValidUTF8(Value));
   Assert(Pos(#0, Value) = 0);
   FValue := FValue + Value + #0;
end;

procedure TStringStreamWriter.WriteBoolean(const Value: Boolean);
begin
   if (Value) then
      FValue := FValue + 'T' + #0
   else
      FValue := FValue + 'F' + #0;
end;

procedure TStringStreamWriter.Close();
begin
   ProcessValue(FValue);
   {$IFOPT C+} FClosed := True; {$ENDIF}
end;

{$IFOPT C+}
destructor TStringStreamWriter.Destroy();
begin
   Assert(FClosed);
   inherited;
end;
{$ENDIF}


{$IFDEF DEBUG}
constructor TStringStreamWriterDebug.Create(Expectation: UTF8String);
begin
   inherited Create();
   FExpectation := Expectation;
end;

procedure TStringStreamWriterDebug.ProcessValue(const Value: UTF8String);
begin
   if (Value = FExpectation) then
      FSuccess := True
   else
      Writeln('Expected '#10'"', FExpectation, '", but got:'#10'"', Value, '"');
end;
{$ENDIF}

end.
