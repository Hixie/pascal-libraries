{$MODE OBJFPC} { -*- delphi -*- }
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
      function ReadLongint(): Longint;
      function ReadCardinal(): Cardinal; // only supports values up to High(Longint)
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
      FClosed: Boolean;
    protected
      {$IFOPT C+} function GetDebugStarted(): Boolean; {$ENDIF}
    public
      constructor Create();
      procedure WriteLongint(const Value: Longint);
      procedure WriteCardinal(const Value: Cardinal);
      procedure WriteDouble(const Value: Double);
      procedure WriteString(const Value: UTF8String);
      procedure WriteBoolean(const Value: Boolean);
      procedure Reset();
      procedure Close();
      function Serialize(): UTF8String;
      property Closed: Boolean read FClosed;
      {$IFOPT C+} property DebugStarted: Boolean read GetDebugStarted; {$ENDIF}
   end;

implementation

uses
   sysutils, exceptions, utf8 {$IFOPT C+}, math {$ENDIF};

const FloatFormat: TFormatSettings = (
   CurrencyFormat: 1;
   NegCurrFormat: 1;
   ThousandSeparator: ',';
   DecimalSeparator: '.';
   CurrencyDecimals: 2;
   DateSeparator: '-';
   TimeSeparator: ':';
   ListSeparator: ',';
   CurrencyString: '$';
   ShortDateFormat: 'yyyy-mm-dd';
   LongDateFormat: 'dd" "mmmm" "yyyy';
   TimeAMString: 'AM';
   TimePMString: 'PM';
   ShortTimeFormat: 'hh:nn';
   LongTimeFormat: 'hh:nn:ss';
   ShortMonthNames: ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
   LongMonthNames: ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
   ShortDayNames: ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
   LongDayNames: ('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');
   TwoDigitYearCenturyWindow: 50
);


constructor TStringStreamReader.Create(const Input: UTF8String);
begin
   Assert(Length(Input) < High(Cardinal));
   FInput := Input;
end;

function TStringStreamReader.ReadUntilNull(const Terminal: Char): UTF8String;
var
   Start: Cardinal;
begin
   Start := FPosition+1; // $R-
   repeat
      Inc(FPosition);
      if (FPosition > Length(FInput)) then
      begin
         Result := '';
         Close();
         exit;
      end;
   until (FInput[FPosition] = Terminal);
   Result := Copy(FInput, Start, FPosition - Start);
end;

procedure TStringStreamReader.Close();
begin
   // move pointer to past the end
   FPosition := Length(FInput)+1; // $R-
end;

function TStringStreamReader.ReadCardinal(): Cardinal;
var
   Value: Int64;
begin
   Value := StrToInt64Def(ReadUntilNull(), Low(Int64));
   if ((Value < Low(Cardinal)) or (Value > High(Cardinal))) then
   begin
      Value := 0;
      Close();
   end;
   Result := Value; // $R-
end;

function TStringStreamReader.ReadLongint(): Longint;
var
   Value: Int64;
begin
   Value := StrToInt64Def(ReadUntilNull(), Low(Int64));
   if ((Value < Low(Longint)) or (Value > High(Longint))) then
   begin
      Value := 0;
      Close();
   end;
   Result := Value; // $R-
end;

function TStringStreamReader.ReadDouble(): Double;
begin
   Result := StrToFloatDef(ReadUntilNull(), 0.0, FloatFormat); // $R-
end;

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

{$IFOPT C+}
function TStringStreamWriter.GetDebugStarted(): Boolean;
begin
   Result := FValue <> '';
end;
{$ENDIF}

// TODO: this should not keep copying the string around

procedure TStringStreamWriter.WriteCardinal(const Value: Cardinal);
begin
   FValue := FValue + IntToStr(Value) + #0;
end;

procedure TStringStreamWriter.WriteLongint(const Value: Longint);
begin
   FValue := FValue + IntToStr(Value) + #0;
end;

procedure TStringStreamWriter.WriteDouble(const Value: Double);
begin
   Assert(not IsInfinite(Value));
   Assert(not IsNaN(Value));
   FValue := FValue + FloatToStrF(Value, ffExponent, 15, 0, FloatFormat) + #0;
end;

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

procedure TStringStreamWriter.Reset();
begin
   Assert(not FClosed);
   FValue := '';
end;

procedure TStringStreamWriter.Close();
begin
   Assert(not FClosed);
   FClosed := True;
end;

function TStringStreamWriter.Serialize(): UTF8String;
begin
   Assert(FClosed);
   Result := FValue;
end;
   
end.
