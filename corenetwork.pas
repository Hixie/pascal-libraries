{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit corenetwork;

interface

//{$DEFINE VERBOSE_NETWORK}
//{$DEFINE VERBOSE_NETWORK_WITH_STACK_TRACES}
//{$DEFINE SUPER_VERBOSE_SEND}
//{$DEFINE SUPER_VERBOSE_READ}

uses
   baseunix, unixtype, sockets, exceptions;

const
   timeoutForever = -1;
   DefaultMaxBuffer = 1024 * 160; // max buffer 160KB per connection

type
   TBaseSocket = class;
   TListenerSocket = class;
   TNetworkSocket = class;

   TNewConnectionEvent = procedure (ListenerSocket: TListenerSocket) of object;
   TDisconnectEvent = procedure (Socket: TBaseSocket) of object;
   TOverflowEvent = procedure (Socket: TNetworkSocket) of object;

   TBaseSocket = class
    protected
      FConnected: Boolean;
      FOnDisconnect: TDisconnectEvent;
      FSocketNumber: cint;
      function GetWriteDataPending(): Boolean; virtual; abstract;
    public
      procedure ReportConnectionError(ErrorCode: cint); virtual;
      procedure Disconnect(); virtual; abstract;
      function Read(): Boolean; virtual; abstract;
      property Connected: Boolean read FConnected;
      property OnDisconnect: TDisconnectEvent read FOnDisconnect write FOnDisconnect;
      property WriteDataPending: Boolean read GetWriteDataPending;
   end;

   TListenerSocket = class(TBaseSocket)
    protected
      FOnNewConnection: TNewConnectionEvent;
      FPort: Word;
      function GetWriteDataPending(): Boolean; override;
    public
      constructor Create(Port: Word);
      destructor Destroy(); override;
      procedure Disconnect(); override;
      function Read(): Boolean; override;
      property OnNewConnection: TNewConnectionEvent read FOnNewConnection write FOnNewConnection;
   end;

   TNetworkSocket = class(TBaseSocket)
    protected
      FAddr: TINetSockAddr;
      FPendingWrites: Pointer;
      FPendingWritesLength: Cardinal;
      FMaxBufferSize: Cardinal;
      FOnOverflow: TOverflowEvent;
      function InternalRead(Data: array of byte): Boolean; virtual; abstract; // return false if connection is bad
      function GetWriteDataPending(): Boolean; override;
      procedure ConnectIpV4(Host: DWord; Port: Word);
      procedure Preconnect(); virtual;
    public
      constructor Create(Listener: TListenerSocket); overload;
      constructor Create(); overload;
      destructor Destroy(); override;
      procedure Disconnect(); override;
      function Read(): Boolean; override;
      procedure Write(); // flush buffer
      procedure Write(const S: RawByteString); { Do not pass an empty string }
      procedure Write(const S: array of Byte); { Do not pass an empty array }
      procedure Write(const S: Pointer; const Len: Cardinal);
      property MaxBufferSize: Cardinal read FMaxBufferSize write FMaxBufferSize;
      property OnOverflow: TOverflowEvent read FOnOverflow write FOnOverflow;
   end;

   PSocketListItem = ^TSocketListItem;
   TSocketListItem = record
     Next: PSocketListItem;
     Value: TBaseSocket;
   end;

   TNetworkServer = class
    protected
      FList: PSocketListItem;
      FHavePendingDisconnects: Boolean;
      FSocketCount: Cardinal;
      procedure Add(Socket: TBaseSocket);
      procedure Remove(Socket: TBaseSocket);
      procedure Empty();
      procedure HandleNewConnection(ListenerSocket: TListenerSocket);
      procedure HandleDisconnect(Socket: TBaseSocket);
      procedure HandleOverflow(Socket: TNetworkSocket);
      function CreateNetworkSocket(ListenerSocket: TListenerSocket): TNetworkSocket; virtual; abstract;
    public
      constructor Create();
      constructor Create(Port: Word); // automatically creates a listener
      destructor Destroy(); override;
      function AddListener(const Port: Word): TListenerSocket;
      function Select(Timeout: cint): Boolean; // timeoutForever (-1) or time in milliseconds; returns True if timed out
   end;

implementation

uses
   sysutils {$IFDEF LINUX}, linux {$ENDIF} {$IFDEF VERBOSE_NETWORK}, errors {$ENDIF}; // errors is for StrError

// {$DEFINE DISABLE_NAGLE} // should not be necessary

procedure TBaseSocket.ReportConnectionError(ErrorCode: cint);
begin
end;

constructor TListenerSocket.Create(Port: Word);
var
   Addr: TINetSockAddr;
   Argument: Integer;
begin
   inherited Create();
   FPort := Port;
   FSocketNumber := fpSocket(AF_INET, SOCK_STREAM, 0);
   if (FSocketNumber < 0) then
      raise ESocketError.Create(SocketError);
   Argument := 1;
   fpSetSockOpt(FSocketNumber, SOL_SOCKET, SO_REUSEADDR, @Argument, SizeOf(Argument));
   Addr.sin_family := AF_INET;
   Addr.sin_addr.s_addr := htonl(INADDR_ANY);
   Addr.sin_port := htons(FPort);
   if (fpBind(FSocketNumber, PSockAddr(@Addr), SizeOf(Addr)) <> 0) then
      raise ESocketError.Create(SocketError);
   if (fpListen(FSocketNumber, 32) <> 0) then // allow up to 32 pending connections at once
      raise ESocketError.Create(SocketError);
   FConnected := True;
end;

destructor TListenerSocket.Destroy();
begin
   Assert(not FConnected);
   inherited;
end;

procedure TListenerSocket.Disconnect();
begin
   if (FConnected) then
   begin
      if (Assigned(FOnDisconnect)) then
         FOnDisconnect(Self);
      if (fpClose(FSocketNumber) <> 0) then
         raise EKernelError.Create(fpGetErrNo);
   end;
   FConnected := False;
end;

function TListenerSocket.Read(): Boolean;
begin
   Assert(FConnected);
   Assert(Assigned(FOnNewConnection));
   FOnNewConnection(Self);
   Result := True;
end;

function TListenerSocket.GetWriteDataPending(): Boolean;
begin
   Result := False;
end;


constructor TNetworkSocket.Create(Listener: TListenerSocket);
var
   Options: cint;
   AddrLen: PSockLen;
   {$IFDEF DISABLE_NAGLE}
   Argument: Integer;
   {$ENDIF}
begin
   inherited Create();
   FMaxBufferSize := DefaultMaxBuffer;
   New(AddrLen);
   AddrLen^ := SizeOf(FAddr);
   FSocketNumber := fpAccept(Listener.FSocketNumber, PSockAddr(@FAddr), AddrLen);
   Dispose(AddrLen);
   if (FSocketNumber < 0) then
      raise ESocketError.Create(SocketError);
   Options := FpFcntl(FSocketNumber, F_GETFL);
   if (Options < 0) then
      raise EKernelError.Create(fpGetErrNo);
   Options := FpFcntl(FSocketNumber, F_SETFL, Options or O_NONBLOCK);
   if (Options < 0) then
      raise EKernelError.Create(fpGetErrNo);
   {$IFDEF DISABLE_NAGLE}
   Argument := 1;
   fpSetSockOpt(FSocketNumber, IPPROTO_TCP, TCP_NODELAY, @Argument, SizeOf(Argument));
   {$ENDIF}
   Preconnect();
   {$IFDEF VERBOSE_NETWORK} Writeln('TNetworkSocket.Create() for ', FSocketNumber); {$ENDIF}
end;

constructor TNetworkSocket.Create();
begin
   inherited Create();
end;

procedure TNetworkSocket.ConnectIpV4(Host: DWord; Port: Word);
var
   ConnectResult: cint;
   Address: PSockAddr;
   {$IFOPT C+} Options: cint; {$ENDIF}
   {$IFDEF DISABLE_NAGLE}
   Argument: Integer;
   {$ENDIF}
begin
   Assert(not FConnected);
   New(Address);
   Address^.sin_family := AF_INET;
   Address^.sin_addr.s_addr := HToNL(Host);
   Address^.sin_port := HToNS(Port);
   try
      FSocketNumber := fpSocket(Address^.sin_family, SOCK_STREAM or O_NONBLOCK, 0);
      if (FSocketNumber < 0) then
         raise ESocketError.Create(SocketError);
      ConnectResult := fpConnect(FSocketNumber, Address, SizeOf(SockAddr));
      if ((ConnectResult < 0) and (SocketError <> EINPROGRESS)) then
         raise ESocketError.Create(SocketError);
   finally
      Dispose(Address);
   end;
   {$IFOPT C+}
   Options := FpFcntl(FSocketNumber, F_GETFL);
   Assert(Options and O_NONBLOCK > 0);
   {$ENDIF}
   {$IFDEF DISABLE_NAGLE}
   Argument := 1;
   fpSetSockOpt(FSocketNumber, IPPROTO_TCP, TCP_NODELAY, @Argument, SizeOf(Argument));
   {$ENDIF}
   Preconnect();
   {$IFDEF VERBOSE_NETWORK} Writeln('TNetworkSocket.ConnectIpV4() for ', FSocketNumber); {$ENDIF}
end;

destructor TNetworkSocket.Destroy();
begin
   Assert(not FConnected);
   if (FPendingWritesLength > 0) then
   begin
      Assert(Assigned(FPendingWrites));
      FreeMem(FPendingWrites, FPendingWritesLength);
      FPendingWrites := nil;
      FPendingWritesLength := 0;
   end;
   inherited;
end;

procedure TNetworkSocket.Preconnect();
begin
   FConnected := True;
end;

procedure TNetworkSocket.Disconnect();
var
   Error: Integer;
begin
   {$IFDEF VERBOSE_NETWORK}
   Writeln('TNetworkSocket.Disconnect() for ', FSocketNumber);
      {$IFDEF VERBOSE_NETWORK_WITH_STACK_TRACES}
      Writeln(GetStackTrace());
      {$ENDIF}
   {$ENDIF}
   if (FConnected) then
   begin
      if (Assigned(FOnDisconnect)) then
         FOnDisconnect(Self);
      Error := fpShutdown(FSocketNumber, 2);
      if ((Error <> 0) and (SocketError <> 107)) then // 107 = already disconnected
      begin
         {$IFDEF DEBUG}
            {$IFDEF VERBOSE_NETWORK} Writeln('Raising the following socket error while disconnecting: ', StrError(SocketError)); {$ENDIF}
            raise ESocketError.Create(SocketError);
         {ELSE}
            {$IFDEF VERBOSE_NETWORK} Writeln('Ignoring the following socket error while disconnecting: ', StrError(SocketError)); {$ENDIF}
         {$ENDIF}
      end;
      if (fpClose(FSocketNumber) <> 0) then
         raise EKernelError.Create(fpGetErrNo);
   end;
   FConnected := False;
end;

function TNetworkSocket.Read(): Boolean;
var
   Data: array of Byte;
   Received: ssize_t;
{$IFDEF SUPER_VERBOSE_READ}
   i: Cardinal;
{$ENDIF}
begin
   if (FConnected) then
   begin
      SetLength(Data, 4096); // smaller than High(size_t)
      Received := fpRecv(FSocketNumber, @Data[0], Length(Data), 0); // $R-
      if (Received > 0) then
      begin
         SetLength(Data, Received); // TODO: this is inefficient and might result in a copy
         {$IFDEF SUPER_VERBOSE_READ}
          system.Write('received: ');
          for i := 0 to Length(Data)-1 do // $R-
             system.Write(Chr(Data[i]));
          Writeln();
          system.Write('                  hex: ');
          for i := 0 to Length(Data)-1 do // $R-
             system.Write(IntToHex(Data[i], 2), ' ');
          Writeln();
         {$ENDIF}
      end
      else
      begin
         // else doesn't matter, Data isn't used
         {$IFDEF VERBOSE_NETWORK} Writeln('peer gracefully disconnected'); {$ENDIF}
      end;
   end;
   // Received=0 means that the peer gracefully disconnected
   // the FConnected guard on the next line isn't understood by the compiler so it thinks
   // that Received and Data might not be initialised
   Result := FConnected and (Received > 0) and InternalRead(Data);
end;

procedure TNetworkSocket.Write();
begin
   {$IFDEF VERBOSE_NETWORK} Writeln('Flushing buffer for socket ', FSocketNumber, '; buffer has ', FPendingWritesLength, ' bytes pending.'); {$ENDIF}
   Write(nil, 0);
end;

procedure TNetworkSocket.Write(const S: RawByteString);
begin
   Assert(Length(S) > 0);
   Write(@S[1], Length(S)); // $R-
end;

procedure TNetworkSocket.Write(const S: array of byte);
begin
   Assert(Length(S) > 0);
   Write(@S[0], Length(S)); // $R-
end;

procedure TNetworkSocket.Write(const S: Pointer; const Len: Cardinal);

{$IFDEF SUPER_VERBOSE_SEND}
  function fpSend(s: cint; msg: pointer; len: size_t; flags: cint): ssize_t;
  var
     i: Cardinal;
  begin
     system.Write('fpSend called to send: ');
     for i := 0 to len-1 do // $R-
        system.Write(Chr(Byte((Msg+i)^)));
     Writeln();
     system.Write('                  hex: ');
     for i := 0 to len-1 do // $R-
        system.Write(IntToHex(Byte((Msg+i)^), 2), ' ');
     Writeln();
        {$IFDEF VERBOSE_NETWORK_WITH_STACK_TRACES}
        Writeln(GetStackTrace());
        {$ENDIF}
     Result := Sockets.fpSend(s, msg, len, flags);
  end;
{$ENDIF}

var
   Sent: ssize_t;
   OldBuffer: Pointer;
   NeedCopy: Boolean;
begin
   if (not FConnected) then
   begin
      {$IFDEF VERBOSE_NETWORK} Writeln('Writing to socket ', FSocketNumber, ' when disconnected; ignored.'); {$ENDIF}
      exit; // Don't bother doing any work if we're not going to send it anyway
   end;
   if (Len > 0) then
   begin
      if (Len > FMaxBufferSize) then
         FMaxBufferSize := Len;
      Assert(Assigned(S));
      if (FPendingWritesLength > 0) then
      begin
         Assert(Assigned(FPendingWrites));
         ReallocMem(FPendingWrites, FPendingWritesLength + Len);
         {$POINTERMATH ON}
         Move(S^, (FPendingWrites + FPendingWritesLength)^, Len);
         {$POINTERMATH OFF}
         Inc(FPendingWritesLength, Len);
         NeedCopy := False;
      end
      else
      begin
         Assert(not Assigned(FPendingWrites));
         FPendingWrites := S;
         FPendingWritesLength := Len;
         NeedCopy := True;
      end;
   end
   else // we are called with Len=0 when the select loop just wants us to try flushing our buffer
      NeedCopy := False;
   // if we get here and FPendingWritesLength = 0, that probably means
   // that we were called once and failed to send everything, then
   // immediately called again and successfully sent everything that
   // time, and only then did the select loop get around to us.
   if (FPendingWritesLength > 0) then
   begin
      // MSG_NOSIGNAL suppresses SIGPIPE on Linux (turns it into EPIPE instead)
      FpSetErrNo(Low(SocketError)); // sentinel so we can tell if failure happened without any error code (otherwise we might see ESysENoTTY)
      Sent := fpSend(FSocketNumber, FPendingWrites, FPendingWritesLength, {$IFDEF Linux} MSG_NOSIGNAL {$ELSE} 0 {$ENDIF});
      {$IFDEF DEBUG} {$IFNDEF TESTSUITE} Sleep(50); {$ENDIF} {$ENDIF}
      if (Sent < FPendingWritesLength) then
      begin
         if (((Sent >= 0) or
              (SocketError = ESysEAgain) or
              (SocketError = ESysEWouldBlock) or
              (SocketError = ESysEIntr)) and
             (FPendingWritesLength - Sent <= FMaxBufferSize)) then
         begin
            if (Sent > 0) then
            begin
               OldBuffer := FPendingWrites;
               Assert(FPendingWritesLength > Sent);
               Dec(FPendingWritesLength, Sent);
               FPendingWrites := GetMem(FPendingWritesLength);
               {$POINTERMATH ON}
               Move((OldBuffer + Sent)^, FPendingWrites^, FPendingWritesLength);
               {$POINTERMATH OFF}
               if (not NeedCopy) then
                  FreeMem(OldBuffer, FPendingWritesLength + Sent); // $R-
            end
            else
            if (NeedCopy) then
            begin
               OldBuffer := FPendingWrites;
               FPendingWrites := GetMem(FPendingWritesLength);
               Move(OldBuffer^, FPendingWrites^, FPendingWritesLength);
            end;
            Assert(FConnected);
            {$IFDEF DEBUG}
            {$IFDEF VERBOSE_NETWORK} Writeln('Had overflow sending data to socket number ', FSocketNumber, '; sent ', Sent, ' bytes, now have ', FPendingWritesLength, ' bytes left to send.'); {$ENDIF}
            {$ENDIF}
            if (Assigned(FOnOverflow)) then
            begin
               FOnOverflow(Self);
            end;
         end
         else
         begin
            {$IFDEF VERBOSE_NETWORK} Writeln('Handling network socket error ', SocketError, ' (', StrError(SocketError), '); PendingWritesLength=', FPendingWritesLength, ', Sent=', Sent, ', MaxBufferSize=', FMaxBufferSize); {$ENDIF}
            if (NeedCopy) then
            begin
               // don't bother getting a copy of the buffer
               FPendingWrites := nil;
               FPendingWritesLength := 0;
            end; // else, keep on to buffer until we are freed
            {$IFDEF DEBUG}
            // mostly for fun, document what error codes you get here
            // (the real reason is to find out if there's codes we'll get that are actual problems we should deal with)
            // see the man page for unix send(), |man 7 tcp|, and |man 7 ip| for descriptions of other possible codes
            if ((SocketError <> Low(SocketError)) and // our sentinel value; see FpSetErrNo call above; we probably overflowed FMaxBufferSize
                (SocketError <> ESysEPipe) and // 32 = broken pipe (i.e. other side disconnected in some manner)
                (SocketError <> ESysEConnReset) and // 104 = connection reset by peer
                (SocketError <> ESysETimedOut) and // 110 = connection timed out
                (SocketError <> ESysEConnRefused) and // 111 = connection refused
                (SocketError <> ESysEHostUnreach) and // 113 = no route to host
                // (SocketError <> ESysENoTTY) and // 25 = not a typewriter (inappropriate ioctl for device) // should never see this, we don't call ioctl here
                (SocketError <> ESysENotConn) and // 107 = transport endpoint is not connected
                (SocketError <> ESysEAgain) and // from above (means we overflowed FMaxBufferSize)
                (SocketError <> ESysEWouldBlock) and // from above (means we overflowed FMaxBufferSize)
                (SocketError <> ESysEIntr)) then // from above (means we overflowed FMaxBufferSize)
            begin
               // If we get here, the error is a new one that we don't know about. In debug mode, throw an exception so that
               // we notice the error and do something about it (probably just adding it to the list above).
               {$IFDEF VERBOSE_NETWORK} Writeln('  Raising exception; this is a new error that we haven''t seen before.'); {$ENDIF}
               raise ESocketError.Create(SocketError); // this is only done in debug mode
            end;
            {$IFDEF VERBOSE_NETWORK} Writeln('  Closing connection.'); {$ENDIF}
            {$ENDIF}
            ReportConnectionError(SocketError);
            Disconnect();
         end;
      end
      else
      begin
         if (not NeedCopy) then
            FreeMem(FPendingWrites, FPendingWritesLength);
         FPendingWrites := nil;
         FPendingWritesLength := 0;
      end;
   end
   else
   begin
      Assert(Len = 0);
      Assert(not Assigned(FPendingWrites));
      Assert(not NeedCopy);
   end;
end;

function TNetworkSocket.GetWriteDataPending(): Boolean;
begin
   Result := FPendingWritesLength > 0;
end;


constructor TNetworkServer.Create();
begin
   inherited Create();
end;

constructor TNetworkServer.Create(Port: Word);
begin
   Create();
   AddListener(Port);
end;

destructor TNetworkServer.Destroy();
begin
   Empty();
   inherited;
end;

function TNetworkServer.AddListener(const Port: Word): TListenerSocket;
begin
   Result := TListenerSocket.Create(Port);
   Result.OnNewConnection := @Self.HandleNewConnection;
   Add(Result);
end;

procedure TNetworkServer.Add(Socket: TBaseSocket);
var
   Item: PSocketListItem;
begin
   New(Item);
   Item^.Next := FList;
   Item^.Value := Socket;
   FList := Item;
   Inc(FSocketCount);
   Socket.OnDisconnect := @Self.HandleDisconnect;
   if (Socket is TNetworkSocket) then
      (Socket as TNetworkSocket).OnOverflow := @Self.HandleOverflow;
end;

procedure TNetworkServer.Remove(Socket: TBaseSocket);
var
   Item: PSocketListItem;
   Last: ^PSocketListItem;
begin
   // this acts like the disconnect logic at the end of Select()
   Last := @FList;
   Item := FList;
   while (Assigned(Item)) do
   begin
      if (Item^.Value = Socket) then
      begin
         Last^ := Item^.Next;
         Dispose(Item);
         Item := nil;
         Dec(FSocketCount);
      end
      else
      begin
         Last := @Item^.Next;
         Item := Item^.Next;
      end;
   end;
end;

procedure TNetworkServer.Empty();
var
   Item: PSocketListItem;
begin
   while (Assigned(FList)) do
   begin
      Item := FList;
      FList := FList^.Next;
      Assert(Assigned(Item^.Value));
      Item^.Value.Disconnect();
      Item^.Value.Destroy();
      Dispose(Item);
   end;
   FSocketCount := 0;
end;

procedure TNetworkServer.HandleNewConnection(ListenerSocket: TListenerSocket);
begin
   Add(CreateNetworkSocket(ListenerSocket));
end;

procedure TNetworkServer.HandleDisconnect(Socket: TBaseSocket);
begin
   FHavePendingDisconnects := True;
end;

procedure TNetworkServer.HandleOverflow(Socket: TNetworkSocket);
{$IFOPT C+}
var
   Item: PSocketListItem;
{$ENDIF}
begin
   // this just asserts that the given socket is in fact in the list of sockets
   {$IFOPT C+}
   Item := FList;
   while (Assigned(Item)) do
   begin
      if (Item^.Value = Socket) then
         break;
      Item := Item^.Next;
   end;
   Assert(Assigned(Item));
   {$ENDIF}
end;

function TNetworkServer.Select(Timeout: cint): Boolean;
var
   Index: Cardinal;
   Pending: cint;
   PollArray: array of PollFD;
   Item: PSocketListItem;
   Last: ^PSocketListItem;
   Disconnect: Boolean;
begin
   Result := False;
   if (FSocketCount = 0) then
     exit;
   SetLength(PollArray, FSocketCount);
   Index := 0;
   Item := FList;
   while (Assigned(Item)) do
   begin
      PollArray[Index].fd := Item^.Value.FSocketNumber;
      if (Item^.Value.WriteDataPending) then
      begin
         PollArray[Index].events := POLLIN or POLLOUT;
      end
      else
      begin
         PollArray[Index].events := POLLIN;
      end;
      Item := Item^.Next;
      Inc(Index);
   end;
   Assert(Index = FSocketCount);
   Pending := fpPoll(@PollArray[0], FSocketCount, Timeout);
   if (Pending < 0) then
   begin
      {$IFDEF VERBOSE_NETWORK} Writeln('poll returned ', Pending, '; error is ', fpGetErrNo); {$ENDIF}
      case fpGetErrNo of
         ESysEIntr: exit; { probably received ^C or an alarm }
      else
         raise EKernelError.Create(fpGetErrNo);
      end;
   end;
   if (Pending = 0) then
   begin
      {$IFDEF VERBOSE_NETWORK} Writeln('poll returned zero, assuming timeout'); {$ENDIF}
      Result := True;
      exit;
   end;
   Item := FList;
   Index := 0;
   while ((Pending > 0) and Assigned(Item)) do
   begin
      Assert(PollArray[Index].fd = Item^.Value.FSocketNumber);
      Disconnect := False;
      // check if this socket was flagged for reading
      if ((PollArray[Index].revents and POLLIN) > 0) then
      begin
         Dec(Pending);
         {$IFDEF VERBOSE_NETWORK} Writeln('poll() reported data available on socket ', Item^.Value.FSocketNumber); {$ENDIF}
         try
            if (not Item^.Value.Read()) then
            begin
               {$IFDEF VERBOSE_NETWORK} Writeln('error reading on socket ', Item^.Value.FSocketNumber); {$ENDIF}
               Disconnect := True;
            end;
         except
            on E: Exception do
            begin
               ReportCurrentException();
               {$IFDEF VERBOSE_NETWORK} Writeln('exception caught while handling read for socket ', Item^.Value.FSocketNumber); {$ENDIF}
               Disconnect := True;
            end;
         end;
      end;
      // check if this socket was flagged for writing
      if ((PollArray[Index].revents and POLLOUT) > 0) then
      begin
         Dec(Pending);
         Assert(Item^.Value is TNetworkSocket);
         {$IFDEF VERBOSE_NETWORK} Writeln('poll() reported write buffer ready for data for socket ', Item^.Value.FSocketNumber); {$ENDIF}
         (Item^.Value as TNetworkSocket).Write(); // can call its own Disconnect()
      end;
      // check if this socket was flagged for some sort of problem
      if ((PollArray[Index].revents and (POLLERR or POLLNVAL)) > 0) then
      begin
         Dec(Pending);
         Assert(Item^.Value is TNetworkSocket);
         {$IFDEF VERBOSE_NETWORK} Writeln('poll() reported i/o exception for socket ', Item^.Value.FSocketNumber); {$ENDIF}
         Disconnect := True;
      end;
      // 
      if ((PollArray[Index].revents and (POLLHUP {$IFDEF LINUX} or POLLRDHUP {$ENDIF})) > 0) then
      begin
         Dec(Pending);
         Assert(Item^.Value is TNetworkSocket);
         {$IFDEF VERBOSE_NETWORK} Writeln('poll() reported remote disconnect for socket ', Item^.Value.FSocketNumber); {$ENDIF}
         // XXX now what?
      end;
      // clean up and move on
      if (Disconnect) then
         Item^.Value.Disconnect();
      Item := Item^.Next;
      Inc(Index);
   end;
   {$IFDEF VERBOSE}
   if (Pending <> 0) then
   begin
      Writeln('Poll call returned a different number of pending sockets than we could account for.');
      Writeln('Original pending count: ', OriginalPending, '; Remainder: ', Pending);
      Writeln('Currently open sockets: ');
      Item := FList;
      while (Assigned(Item)) do
      begin
         Writeln('  ', Item^.Value.FSocketNumber);
         Item := Item^.Next;
      end;      
   end;
   {$ENDIF}
   if (FHavePendingDisconnects) then
   begin
      Last := @FList;
      Item := FList;
      while (Assigned(Item)) do
      begin
         if (not Item^.Value.Connected) then
         begin
            Assert(Last^ = Item);
            // act like Remove()
            Assert(Assigned(Item^.Value));
            Item^.Value.Destroy();
            {$IFDEF C+} Item^.Value := nil; {$ENDIF}
            Last^ := Item^.Next;
            Dispose(Item);
            Item := Last^;
            Dec(FSocketCount);
         end
         else
         begin
            Last := @Item^.Next;
            Item := Item^.Next;
         end;
      end;
      FHavePendingDisconnects := False;
   end;
end;

end.
