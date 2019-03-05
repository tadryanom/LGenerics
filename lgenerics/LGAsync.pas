{****************************************************************************
*                                                                           *
*   This file is part of the LGenerics package.                             *
*   Some asynchronous primitives.                                           *
*                                                                           *
*   Copyright(c) 2018-2019 A.Koverdyaev(avk)                                *
*                                                                           *
*   This code is free software; you can redistribute it and/or modify it    *
*   under the terms of the Apache License, Version 2.0;                     *
*   You may obtain a copy of the License at                                 *
*     http://www.apache.org/licenses/LICENSE-2.0.                           *
*                                                                           *
*  Unless required by applicable law or agreed to in writing, software      *
*  distributed under the License is distributed on an "AS IS" BASIS,        *
*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. *
*  See the License for the specific language governing permissions and      *
*  limitations under the License.                                           *
*                                                                           *
*****************************************************************************}
unit LGAsync;

{$mode objfpc}{$H+}
{$INLINE ON}
{$MODESWITCH NESTEDPROCVARS}

interface

uses
  Classes,
  SysUtils,
  LGUtils,
  LGQueue,
  LGVector,
  LGPriorityQueue,
  LGFunction,
  LGStrConst;

type

  TAsyncTaskState = (astPending, astExecuting, astFinished);
  TFutureState    = (fsPending, fsExecuting, fsFinished, fsResolved, fsFatal, fsCancelled);

{$PUSH}{$INTERFACES COM}
  IAsyncTask = interface(ITask)
  ['{4122B5EC-40CF-421D-AFB8-23534663C24E}']
    function  GetRefCount: Integer;
    function  GetState: TAsyncTaskState;
    procedure WaitFor;
    function  FatalException: Exception;
    property  RefCount: Integer read GetRefCount;
    property  State: TAsyncTaskState read GetState;
  end;

  generic IGCallable<T> = interface
  ['{EF605AA3-4E0F-4C52-9A75-5068D94ECDAF}']
    function Call: T;
  end;

  generic IGAsyncTask<T> = interface(IAsyncTask)
  ['{29B0A51F-346F-449F-A232-50697E7B5166}']
    function GetResult: T;
    property Result: T read GetResult;
  end;

  generic IGFuture<T> = interface
  ['{87217C99-9D75-46CC-837A-44624C60C004}']
    function  GetState: TFutureState;
    function  WaitFor: TFutureState;
    procedure Cancel;
  { raises exception if resolving failed }
    function  Value: T;
    function  GetValue: specialize TGOptional<T>;
    property  State: TFutureState read GetState;
  end;
{$POP}

{$PUSH}{$INTERFACES CORBA}
  IExecutor = interface
  ['{49381C21-82D6-456E-93A2-B8E0DC4B34BA}']
    procedure EnqueueTask(aTask: IAsyncTask);
  end;
{$POP}

  { TAsyncTask }
  TAsyncTask = class abstract(TInterfacedObject, ITask, IAsyncTask)
  strict private
    FAwait: PRtlEvent;
    FException: Exception;
    FState: SizeUInt;
  strict protected
    function  GetState: TAsyncTaskState; inline;
    function  GetRefCount: Integer;
  { to override in descendants }
    procedure DoExecute; virtual; abstract;
  public
    destructor Destroy; override;
    procedure AfterConstruction; override;
    procedure Execute;
    procedure WaitFor;
    function  FatalException: Exception;
  end;

  generic TGAsyncTask<T> = class abstract(TAsyncTask, specialize IGAsyncTask<T>)
  strict protected
    FResult: T; //to be setted inside overriden DoExecute
    function GetResult: T;
  public
    property Result: T read GetResult;
  end;

{
  The futures concept describes an asynchronous single-execution pattern.
  Result is requested at an early stage of execution, but becomes available after it is received.
  This implementation implies that futures are intended for use from the main thread.
}
  { TGFuture: takes over the management of the inner async task }
  generic TGFuture<T> = class(TInterfacedObject, specialize IGFuture<T>)
  public
  type
    TOptional = specialize TGOptional<T>;

  private
  type
    ITask = specialize IGAsyncTask<T>;

  strict private
    FTask: ITask;
    FTaskResult: T;
    FState: TFutureState;
    procedure Resolve;
  protected
    function  GetState: TFutureState;
  public
    constructor Create(aTask: ITask; aEx: IExecutor);
    destructor Destroy; override;
    function  WaitFor: TFutureState;
    procedure Cancel;
  { raises exception if resolving failed }
    function  Value: T;
    function  GetValue: TOptional;
    property  State: TFutureState read GetState;
  end;

  { TGAsyncProc incapsulates method without arguments(which returns void), True indicates execution success }
  TGAsyncProc = class(specialize TGAsyncTask<Boolean>)
  public
  type
    TProcedure = procedure of object;
    IFuture    = specialize IGFuture<Boolean>;

  strict private
    FProc: TProcedure;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aProc: TProcedure; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aProc: TProcedure);
  end;

  { TAsyncExecutable incapsulates ITask, True indicates execution success }
  TAsyncExecutable = class(specialize TGAsyncTask<Boolean>)
  public
  type
    IFuture = specialize IGFuture<Boolean>;

  strict private
    FTask: ITask;
  strict protected
    procedure DoExecute; override;
  public
    class function Run(aTask: ITask; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aTask: ITask);
  end;

  { TGAsyncCallable incapsulates IGCallable}
  generic TGAsyncCallable<T> = class(specialize TGAsyncTask<T>)
  public
  type
    ICallable = specialize IGCallable<T>;
    IFuture   = specialize IGFuture<T>;

  strict private
    FTask: ICallable;
  strict protected
    procedure DoExecute; override;
  public
    class function Run(aTask: ICallable; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aTask: ICallable);
  end;

  { TGAsyncMethod incapsulates niladic method(without arguments which returns T) }
  generic TGAsyncMethod<T> = class(specialize TGAsyncTask<T>)
  public
  type
    TFun    = function: T of object;
    IFuture = specialize IGFuture<T>;

  strict private
    FFun: TFun;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aFun: TFun; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aFun: TFun);
  end;

  { TGAsyncNested incapsulates nested niladic function (without arguments) }
  generic TGAsyncNested<T> = class(specialize TGAsyncTask<T>)
  public
  type
    TFun    = function: T is nested;
    IFuture = specialize IGFuture<T>;

  strict private
    FFun: TFun;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aFun: TFun; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aFun: TFun);
  end;

  { TGAsyncNiladic incapsulates regular niladic function (without arguments) }
  generic TGAsyncNiladic<T> = class(specialize TGAsyncTask<T>)
  public
  type
    TFun    = function: T;
    IFuture = specialize IGFuture<T>;

  strict private
    FFun: TFun;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aFun: TFun; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aFun: TFun);
  end;

  { TGAsyncMonadic incapsulates regular monadic function (with one argument) }
  generic TGAsyncMonadic<T, TResult> = class(specialize TGAsyncTask<TResult>)
  strict private
  type
    TCall = specialize TGDeferMonadic<T, TResult>;

  public
  type
    TFun    = TCall.TFun;
    IFuture = specialize IGFuture<TResult>;

  strict private
    FCall: TCall;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aFun: TFun; constref v: T; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aFun: TFun; constref v: T);
  end;

  { TGAsyncDyadic incapsulates regular dyadic function (with two arguments) }
  generic TGAsyncDyadic<T1, T2, TResult> = class(specialize TGAsyncTask<TResult>)
  strict private
  type
    TCall = specialize TGDeferDyadic<T1, T2, TResult>;

  public
  type
    TFun    = TCall.TFun;
    IFuture = specialize IGFuture<TResult>;

  strict private
    FCall: TCall;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aFun: TFun; constref v1: T1; constref v2: T2; aEx: IExecutor = nil): IFuture; static;
    constructor Create(aFun: TFun; constref v1: T1; constref v2: T2);
  end;

  { TGAsyncTriadic incapsulates regular triadic function (with three arguments) }
  generic TGAsyncTriadic<T1, T2, T3, TResult> = class(specialize TGAsyncTask<TResult>)
  strict private
  type
    TCall = specialize TGDeferTriadic<T1, T2, T3, TResult>;

  public
  type
    TFun    = TCall.TFun;
    IFuture = specialize IGFuture<TResult>;

  strict private
    FCall: TCall;
  strict protected
    procedure DoExecute; override;
  public
    class function Call(aFun: TFun; constref v1: T1; constref v2: T2; constref v3: T3;
                        aEx: IExecutor = nil): IFuture; static;
    constructor Create(aFun: TFun; constref v1: T1; constref v2: T2; constref v3: T3);
  end;

const
  DEFAULT_POOL_SIZE = 4;

type
  { TDefaultExecutor executes futures in its own thread pool.
    Enqueue procedure is threadsafe, so futures may use other futures.
    Resizing of thread pool is not threadsafe, so MUST be done from main thread. }
  TDefaultExecutor = class
  private
  type
    TTaskQueue = class
    strict private
    type
      TQueue = specialize TGLiteQueue<IAsyncTask>;

    var
      FQueue: TQueue;
      FReadAwait: PRtlEvent;
      FLock: TRtlCriticalSection;
      FClosed: Boolean;
    public
      constructor Create;
      destructor Destroy; override;
      procedure AfterConstruction; override;
      procedure Clear;
      procedure Close;
      procedure Open;
      procedure Enqueue(aTask: IAsyncTask);
      function  Dequeue(out aTask: IAsyncTask): Boolean;
      function  GetCount: SizeInt; // not syncronized
    end;

    TWorkThread = class(TThread)
    strict private
      FQueue: TTaskQueue;
    public
      constructor Create(aQueue: TTaskQueue);
      procedure Execute; override;
    end;

    TThreadPool = specialize TGLiteVector<TWorkThread>;

    TExecutor = class(TObject, IExecutor)
    private
      FTaskQueue: TTaskQueue;
      FThreadPool: TThreadPool;
      function  ThreadCount: Integer; inline;
      function  AddThread: TWorkThread;
      procedure PoolGrow(aValue: Integer);
      procedure PoolShrink(aValue: Integer);
      procedure TerminatePool;
      procedure FinalizePool; inline;
    public
      constructor Create; overload;
      constructor Create(aThreadCount: Integer); overload;
      destructor  Destroy; override;
      procedure EnqueueTask(aTask: IAsyncTask);
      function  Unhandled: SizeInt;
    end;

    class constructor Init;
    class destructor  Done;
    class function    GetThreadCount: Integer; static; inline;
    class procedure   SetThreadCount(aValue: Integer); static;
  class var
    CFExecutor: TExecutor; // CF -> Class Field

  public
    class procedure EnsureThreadCount(aValue: Integer); static;
    class procedure Enqueue(aTask: IAsyncTask); static;
    class function  GetInstance: IExecutor; static;
  { for estimate purpose only }
    class function  UnhandledCount: SizeInt;
    class property  ThreadCount: Integer read GetThreadCount write SetThreadCount;
  end;

const
  DEFAULT_CHAN_SIZE = 256;
  CHAN_SIZE_UNBOUND = High(SizeInt);

type

  { TGBlockChannel }
  generic TGBlockChannel<T> = class
  strict protected
  type
    IQueue = specialize IGQueue<T>;

  var
    FQueue: IQueue;
    FLock: TRtlCriticalSection;
    FWriteAwait,
    FReadAwait: PRtlEvent;
    FCapacity: SizeInt;
    FWait: Integer;
    FActive: Boolean;
    function  GetWait: Boolean; inline;
    function  GetCapacity: SizeInt; inline;
    procedure SendData(constref aValue: T);
    function  ReceiveData: T;
    class function CreateQueue(aCapacity: SizeInt): IQueue; virtual;
  public
  { param aCapacity specifies capacity of inner queue;
    if aCapacity <= 0 then an unbound channel will be created;
    the creation is not thread-save }
    constructor Create(aCapacity: SizeInt = DEFAULT_CHAN_SIZE);
    destructor Destroy; override;
    procedure AfterConstruction; override;
  { blocking method }
    function  Send(constref aValue: T): Boolean;
  { non blocking method }
    function  TrySend(constref aValue: T): Boolean;
  { blocking method }
    function  Receive(out aValue: T): Boolean;
  { non blocking method }
    function  TryReceive(out aValue: T): Boolean;
  { returns the number of messages in the queue, -1 if not active }
    function  Peek: SizeInt;
    procedure Close;
    procedure Open;
  { if is not Active then Send and Receive will always return False without blocking }
    property  Active: Boolean read FActive;
  { returns True if some thread is waiting for a message }
    property  WaitSend: Boolean read GetWait;
    property  Capacity: SizeInt read GetCapacity;
  end;

  { TGPrioBlockChannel channel with a respect to message priority;
    functor TCmpRel (comparision relation) must provide
      class function Compare([const[ref]] L, R: T): SizeInt }
  generic TGPrioBlockChannel<T, TCmpRel> = class(specialize TGBlockChannel<T>)
  strict protected
    class function CreateQueue(aCapacity: SizeInt): IQueue; override;
  end;

  generic TGBlockPrioChannel<T> = class(specialize TGPrioBlockChannel<T, T>);

  { TGObjBlockChannel }
  generic TGObjBlockChannel<T: class> = class(specialize TGBlockChannel<T>)
  private
  type
    TQueue = specialize TGObjectQueue<T>;

    function  GetOwnsObjects: Boolean; inline;
    procedure SetOwnsObjects(aValue: Boolean); inline;
  strict protected
    class function CreateQueue(aCapacity: SizeInt): IQueue; override;
  public
    constructor Create(aCapacity: SizeInt = DEFAULT_CHAN_SIZE; aOwnsObjects: Boolean = True);
    property OwnsObjects: Boolean read GetOwnsObjects write SetOwnsObjects;
  end;

{$PUSH}{$INTERFACES CORBA}
  IWorkThread = interface
  ['{2C1E3FEF-C538-4506-A0A1-02C0B535B22F}']
    function  GetThreadID: TThreadID;
    function  GetHandle: TThreadID;
    procedure Queue(aMethod: TThreadMethod);
    procedure Synchronize(AMethod: TThreadMethod);
    property  ThreadID: TThreadID read GetThreadID;
    property  Handle: TThreadID read GetHandle;
  end;
{$POP}

  TWorkThread = class(TThread, IWorkThread)
  protected
    function  GetThreadID: TThreadID;
    function  GetHandle: TThreadID;
  end;

  { TGListenThread abstract ancestor class:
    thread that has its own blocking message queue; T is the type of message }
  generic TGListenThread<T> = class abstract
  strict private
  type
    TChannel = specialize TGBlockChannel<T>;

    TWorker = class(TWorkThread)
    private
      FChannel: TChannel;
      FOwner: TGListenThread;
    protected
      procedure Execute; override;
    public
      constructor Create(aOwner: TGListenThread; aChannel: TChannel; aStackSize: SizeUInt);
    end;

  var
    FChannel: TChannel;
    FWorker: TWorker;
    function  GetCapacity: SizeInt;
    function  GetEnqueued: SizeInt;
    function  GetPriority: TThreadPriority;
    procedure SetPriority(aValue: TThreadPriority);
    function  GetThreadID: TThreadID;
    function  GetHandle: TThreadID;
  protected
  { by default do nothing }
    procedure HandleException(constref aMsg: T; aThreed: IWorkThread; e: Exception); virtual;
  { to be overriden in descendants }
    procedure HandleMessage(constref aMessage: T; aThread: IWorkThread); virtual; abstract;
    class function CreateChannel(aCapacity: SizeInt): TChannel; virtual;
  public
  { the creation/destruction is not thread-save;
    param aCapacity specifies capacity of inner queue;
    if aCapacity <= 0 then an unbound inner queue will be created }
    constructor Create(aCapacity: SizeInt = DEFAULT_CHAN_SIZE; aStackSize: SizeUInt = DefaultStackSize);
    destructor Destroy; override;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  { blocking method }
    procedure Send(constref aMessage: T);
  { non blocking method }
    function  TrySend(constref aMessage: T): Boolean;
    property  Priority: TThreadPriority read GetPriority write SetPriority;
    property  ThreadID: TThreadID read GetThreadID;
    property  Handle: TThreadID read GetHandle;
  { returns the number of messages in the inner queue }
    property  Enqueued: SizeInt read GetEnqueued;
    property  Capacity: SizeInt read GetCapacity;
  end;

  { TThreadPool }
  TThreadPool = class
  strict private
  type
    TChannel = specialize TGBlockChannel<ITask>;

    TWorker = class(TWorkThread)
    private
      FChannel: TChannel;
      FOwner: TThreadPool;
    protected
      procedure Execute; override;
    public
      constructor Create(aOwner: TThreadPool; aChannel: TChannel; aStackSize: SizeUInt);
    end;

    TPool = specialize TGLiteVector<TWorker>;

  var
    FChannel: TChannel;
    FPool: TPool;
    FStackSize: SizeInt;
    FLock: TRtlCriticalSection;
    function  GetCapacity: SizeInt;
    function  GetEnqueued: SizeInt;
    function  GetThreadCount: SizeInt;
    procedure SetThreadCount(aValue: SizeInt);
    procedure AddThread;
    procedure PoolGrow(aValue: SizeInt);
    procedure PoolShrink(aValue: SizeInt);
    procedure TerminatePool;
  protected
    procedure Lock; inline;
    procedure Unlock; inline;
  { by default do nothing }
    procedure HandleException(aThreed: IWorkThread; e: Exception); virtual;
  public
  { the creation is not thread-save;
    if aQueueCapacity <= 0 then an unbound inner queue will be created }
    constructor Create(aThreadCount: SizeInt = 0; aQueueCapacity: SizeInt = DEFAULT_CHAN_SIZE;
                       aThreadStackSize: SizeUInt = DefaultStackSize);
    destructor Destroy; override;
    procedure EnsureThreadCount(aValue: SizeInt);
  { blocking method }
    procedure EnqueueTask(aTask: ITask);
  { non blocking method }
    function  TryEnqueueTask(aTask: ITask): Boolean;
    property  ThreadCount: SizeInt read GetThreadCount write SetThreadCount;
  { returns the number of tasks in the inner queue; for estimate purpose only }
    property  Enqueued: SizeInt read GetEnqueued;
    property  Capacity: SizeInt read GetCapacity;
  end;

  { TPrioThreadPool: simple thread pool with a respect to priority of the task }
  TPrioThreadPool = class
  private
  type
    TChannel = specialize TGBlockPrioChannel<IPriorityTask>;

    TWorker = class(TWorkThread)
    private
      FChannel: TChannel;
      FOwner: TPrioThreadPool;
    protected
      procedure Execute; override;
    public
      constructor Create(aOwner: TPrioThreadPool; aChannel: TChannel; aStackSize: SizeUInt);
    end;

    TPool = specialize TGLiteVector<TWorker>;

  var
    FChannel: TChannel;
    FPool: TPool;
    FStackSize: SizeInt;
    FLock: TRtlCriticalSection;
    function  GetCapacity: SizeInt;
    function  GetEnqueued: SizeInt;
    function  GetThreadCount: SizeInt;
    procedure SetThreadCount(aValue: SizeInt);
    procedure AddThread;
    procedure PoolGrow(aValue: SizeInt);
    procedure PoolShrink(aValue: SizeInt);
    procedure TerminatePool;
  protected
    procedure Lock; inline;
    procedure Unlock; inline;
  { by default do nothing }
    procedure HandleException(aThreed: IWorkThread; e: Exception); virtual;
  public
  { the creation is not thread-save;
    if aQueueCapacity <= 0 then an unbound inner queue will be created }
    constructor Create(aThreadCount: SizeInt = 0; aQueueCapacity: SizeInt = DEFAULT_CHAN_SIZE;
                       aThreadStackSize: SizeUInt = DefaultStackSize);
    destructor Destroy; override;
    procedure EnsureThreadCount(aValue: SizeInt);
  { blocking method }
    procedure EnqueueTask(aTask: IPriorityTask);
  { non blocking method }
    function  TryEnqueueTask(aTask: IPriorityTask): Boolean;
    property  ThreadCount: SizeInt read GetThreadCount write SetThreadCount;
  { returns the number of tasks in the inner queue; for estimate purpose only }
    property  Enqueued: SizeInt read GetEnqueued;
    property  Capacity: SizeInt read GetCapacity;
  end;

implementation
{$B-}{$COPERATORS ON}

{ TAsyncTask }

function TAsyncTask.GetState: TAsyncTaskState;
begin
  Result := TAsyncTaskState(FState);
end;

function TAsyncTask.GetRefCount: Integer;
begin
  Result := FRefCount;
end;

destructor TAsyncTask.Destroy;
begin
  System.RtlEventDestroy(FAwait);
  FAwait := nil;
  FException.Free;
  inherited;
end;

procedure TAsyncTask.AfterConstruction;
begin
  inherited;
  FAwait := System.RtlEventCreate;
end;

procedure TAsyncTask.Execute;
begin
{$IFDEF CPU64}
  InterlockedIncrement64(FState);
{$ELSE CPU64}
  InterlockedIncrement(FState);
{$ENDIF CPU64}
  try
    DoExecute;
  except
    on e: Exception do
      FException := Exception(System.AcquireExceptionObject);
  end;
{$IFDEF CPU64}
  InterlockedIncrement64(FState);
{$ELSE CPU64}
  InterlockedIncrement(FState);
{$ENDIF CPU64}
  System.RtlEventSetEvent(FAwait);
end;

procedure TAsyncTask.WaitFor;
begin
  System.RtlEventWaitFor(FAwait);
end;

function TAsyncTask.FatalException: Exception;
begin
  Result := FException;
  FException := nil;
end;

{ TGAsyncTask }

function TGAsyncTask.GetResult: T;
begin
  Result := FResult;
end;

{ TGFuture }

procedure TGFuture.Resolve;
var
  e: Exception = nil;
begin
  if Assigned(FTask) and (State < fsResolved) then
    try
      FTask.WaitFor;
      e := FTask.FatalException;
      if Assigned(e) then
        FState := fsFatal
      else
        begin
          FState := fsResolved;
          FTaskResult := FTask.Result;
        end;
    finally
      FTask := nil;
      if Assigned(e) then
        raise e;
    end;
end;

function TGFuture.GetState: TFutureState;
begin
  if Assigned(FTask) and (FState < fsResolved) then
    try
      case FTask.State of
        astExecuting: FState := fsExecuting;
        astFinished:  FState := fsFinished;
      end;
    except
      FState := fsCancelled;
      Pointer(FTask) := nil;
    end;
  Result := FState;
end;

constructor TGFuture.Create(aTask: ITask; aEx: IExecutor);
begin
  inherited Create;
  FTask := aTask;
  if aEx = nil then
    aEx := TDefaultExecutor.GetInstance;
  aEx.EnqueueTask(FTask);
end;

destructor TGFuture.Destroy;
begin
  FTask := nil;
  inherited;
end;

function TGFuture.WaitFor: TFutureState;
begin
  try
    Resolve;
  except
  end;
  Result := FState;
end;

procedure TGFuture.Cancel;
begin
  if Assigned(FTask) and (FState < fsResolved) then
    begin
      FTask := nil;
      FState := fsCancelled;
    end;
end;

function TGFuture.Value: T;
begin
  case State of
    fsPending..fsFinished:
      Resolve;
    fsFatal:
      raise ELGFuture.Create(SEResultUnknownFatal);
    fsCancelled:
      raise ELGFuture.Create(SEResultUnknownCancel);
  end;
  Result := FTaskResult;
end;

function TGFuture.GetValue: TOptional;
begin
  if WaitFor = fsResolved then
    Result.Assign(FTaskResult);
end;

{ TGAsyncProc }

procedure TGAsyncProc.DoExecute;
begin
  FResult := False;
  FProc();
  FResult := True;
end;

class function TGAsyncProc.Call(aProc: TProcedure; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<Boolean>.Create(TGAsyncProc.Create(aProc), aEx);
end;

constructor TGAsyncProc.Create(aProc: TProcedure);
begin
  inherited Create;
  FProc := aProc;
end;

{ TAsyncExecutable }

procedure TAsyncExecutable.DoExecute;
begin
  FResult := False;
  FTask.Execute;
  FResult := True;
end;

class function TAsyncExecutable.Run(aTask: ITask; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<Boolean>.Create(TAsyncExecutable.Create(aTask), aEx);
end;

constructor TAsyncExecutable.Create(aTask: ITask);
begin
  inherited Create;
  FTask := aTask;
end;

{ TGAsyncCallable }

procedure TGAsyncCallable.DoExecute;
begin
  FResult := FTask.Call;
end;

class function TGAsyncCallable.Run(aTask: ICallable; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<T>.Create(TGAsyncCallable.Create(aTask), aEx);
end;

constructor TGAsyncCallable.Create(aTask: ICallable);
begin
  inherited Create;
  FTask := aTask;
end;

{ TGAsyncMethod }

procedure TGAsyncMethod.DoExecute;
begin
  FResult := FFun();
end;

class function TGAsyncMethod.Call(aFun: TFun; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<T>.Create(TGAsyncMethod.Create(aFun), aEx);
end;

constructor TGAsyncMethod.Create(aFun: TFun);
begin
  inherited Create;
  FFun := aFun;
end;

{ TGAsyncNested }

procedure TGAsyncNested.DoExecute;
begin
  FResult := FFun();
end;

class function TGAsyncNested.Call(aFun: TFun; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<T>.Create(TGAsyncNested.Create(aFun), aEx);
end;

constructor TGAsyncNested.Create(aFun: TFun);
begin
  inherited Create;
  FFun := aFun;
end;

{ TGAsyncNiladic }

procedure TGAsyncNiladic.DoExecute;
begin
  FResult := FFun();
end;

class function TGAsyncNiladic.Call(aFun: TFun; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<T>.Create(TGAsyncNiladic.Create(aFun), aEx);
end;

constructor TGAsyncNiladic.Create(aFun: TFun);
begin
  inherited Create;
  FFun := aFun;
end;

{ TGAsyncMonadic }

procedure TGAsyncMonadic.DoExecute;
begin
  FResult := FCall.Call;
end;

class function TGAsyncMonadic.Call(aFun: TFun; constref v: T; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<TResult>.Create(TGAsyncMonadic.Create(aFun, v), aEx);
end;

constructor TGAsyncMonadic.Create(aFun: TFun; constref v: T);
begin
  inherited Create;
  FCall := TCall.Create(aFun, v);
end;

{ TGAsyncDyadic }

procedure TGAsyncDyadic.DoExecute;
begin
  FResult := FCall.Call;
end;

class function TGAsyncDyadic.Call(aFun: TFun; constref v1: T1; constref v2: T2; aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<TResult>.Create(TGAsyncDyadic.Create(aFun, v1, v2), aEx);
end;

constructor TGAsyncDyadic.Create(aFun: TFun; constref v1: T1; constref v2: T2);
begin
  inherited Create;
  FCall := TCall.Create(aFun, v1, v2);
end;

{ TGAsyncTriadic }

procedure TGAsyncTriadic.DoExecute;
begin
  FResult := FCall.Call;
end;

class function TGAsyncTriadic.Call(aFun: TFun; constref v1: T1; constref v2: T2; constref v3: T3;
  aEx: IExecutor): IFuture;
begin
  Result := specialize TGFuture<TResult>.Create(TGAsyncTriadic.Create(aFun, v1, v2, v3), aEx);
end;

constructor TGAsyncTriadic.Create(aFun: TFun; constref v1: T1; constref v2: T2; constref v3: T3);
begin
  inherited Create;
  FCall := TCall.Create(aFun, v1, v2, v3);
end;

{ TDefaultExecutor.TTaskQueue }

constructor TDefaultExecutor.TTaskQueue.Create;
begin
  inherited;
  System.InitCriticalSection(FLock);
end;

destructor TDefaultExecutor.TTaskQueue.Destroy;
begin
  System.EnterCriticalSection(FLock);
  try
    Finalize(FQueue);
    System.RtlEventDestroy(FReadAwait);
    FReadAwait := nil;
    inherited;
  finally
    System.LeaveCriticalSection(FLock);
    System.DoneCriticalSection(FLock);
  end;
end;

procedure TDefaultExecutor.TTaskQueue.AfterConstruction;
begin
  inherited;
  FReadAwait := System.RtlEventCreate;
end;

procedure TDefaultExecutor.TTaskQueue.Clear;
begin
  System.EnterCriticalSection(FLock);
  try
    FQueue.Clear;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TDefaultExecutor.TTaskQueue.Close;
begin
  System.EnterCriticalSection(FLock);
  try
    FClosed := True;
    System.RtlEventSetEvent(FReadAwait);
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TDefaultExecutor.TTaskQueue.Open;
begin
  System.EnterCriticalSection(FLock);
  try
    FClosed := False;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TDefaultExecutor.TTaskQueue.Enqueue(aTask: IAsyncTask);
begin
  System.EnterCriticalSection(FLock);
  try
    FQueue.Enqueue(aTask);
    System.RtlEventSetEvent(FReadAwait);
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

function TDefaultExecutor.TTaskQueue.Dequeue(out aTask: IAsyncTask): Boolean;
begin
  System.RtlEventWaitFor(FReadAwait);
  System.EnterCriticalSection(FLock);
  try
    if not FClosed then
      begin
        Result := FQueue.TryDequeue(aTask);
        if FQueue.NonEmpty then
         System.RtlEventSetEvent(FReadAwait);
      end
    else
      begin
        Result := False;
        System.RtlEventSetEvent(FReadAwait);
      end;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

function TDefaultExecutor.TTaskQueue.GetCount: SizeInt;
begin
  Result := FQueue.Count;
end;

{ TDefaultExecutor.TWorkThread }

constructor TDefaultExecutor.TWorkThread.Create(aQueue: TTaskQueue);
begin
  inherited Create(True);
  FQueue := aQueue;
end;

procedure TDefaultExecutor.TWorkThread.Execute;
var
  CurrTask: IAsyncTask = nil;
begin
  while not Terminated do
    if FQueue.Dequeue(CurrTask) and (CurrTask.GetRefCount > 1) then
      CurrTask.Execute;
end;

{ TDefaultExecutor.TExecutor }

function TDefaultExecutor.TExecutor.ThreadCount: Integer;
begin
  Result := FThreadPool.Count;
end;

function TDefaultExecutor.TExecutor.AddThread: TWorkThread;
begin
  Result := TWorkThread.Create(FTaskQueue);
  FThreadPool.Add(Result);
  Result.Start;
end;

procedure TDefaultExecutor.TExecutor.PoolGrow(aValue: Integer);
begin
  while FThreadPool.Count < aValue do
    AddThread;
end;

procedure TDefaultExecutor.TExecutor.PoolShrink(aValue: Integer);
begin
  if aValue < 1 then
    aValue := 1;
  TerminatePool;
  FTaskQueue.Open;
  PoolGrow(aValue);
end;

procedure TDefaultExecutor.TExecutor.TerminatePool;
var
  CurrThread: TWorkThread;
begin
  for CurrThread in FThreadPool.Reverse do
    CurrThread.Terminate;
  FTaskQueue.Close;
  while FThreadPool.Count > 0 do
    begin
      CurrThread := FThreadPool.Extract(Pred(FThreadPool.Count));
      CurrThread.WaitFor;
      CurrThread.Free;
    end;
end;

procedure TDefaultExecutor.TExecutor.FinalizePool;
begin
  TerminatePool;
  FThreadPool.Clear;
end;

constructor TDefaultExecutor.TExecutor.Create;
begin
  if TThread.ProcessorCount > DEFAULT_POOL_SIZE then
    Create(TThread.ProcessorCount)
  else
    Create(DEFAULT_POOL_SIZE);
end;

constructor TDefaultExecutor.TExecutor.Create(aThreadCount: Integer);
begin
  FTaskQueue := TTaskQueue.Create;
  if aThreadCount > 0 then
    PoolGrow(aThreadCount)
  else
    PoolGrow(1);
end;

destructor TDefaultExecutor.TExecutor.Destroy;
begin
  FTaskQueue.Clear;
  FinalizePool;
  FTaskQueue.Free;
  inherited;
end;

procedure TDefaultExecutor.TExecutor.EnqueueTask(aTask: IAsyncTask);
begin
  FTaskQueue.Enqueue(aTask);
end;

function TDefaultExecutor.TExecutor.Unhandled: SizeInt;
begin
  Result := FTaskQueue.GetCount;
end;

{ TDefaultExecutor }

class constructor TDefaultExecutor.Init;
begin
  CFExecutor := nil;
end;

class destructor TDefaultExecutor.Done;
begin
  FreeAndNil(CFExecutor);
end;

class function TDefaultExecutor.GetThreadCount: Integer;
begin
  if Assigned(CFExecutor) then
    Result := CFExecutor.ThreadCount
  else
    Result := 0;
end;

class procedure TDefaultExecutor.SetThreadCount(aValue: Integer);
var
  CurrCount: Integer;
begin
  CurrCount := ThreadCount;
  if aValue > CurrCount then
    EnsureThreadCount(aValue)
  else
    if (aValue > 0) and (aValue < CurrCount) then
      CFExecutor.PoolShrink(aValue);
end;

class procedure TDefaultExecutor.EnsureThreadCount(aValue: Integer);
begin
  if aValue > ThreadCount then
    if not Assigned(CFExecutor) then
      CFExecutor := TExecutor.Create(aValue)
    else
      CFExecutor.PoolGrow(aValue);
end;

class procedure TDefaultExecutor.Enqueue(aTask: IAsyncTask);
begin
  if not Assigned(CFExecutor) then
    CFExecutor := TExecutor.Create;
  CFExecutor.EnqueueTask(aTask);
end;

class function TDefaultExecutor.GetInstance: IExecutor;
begin
  if not Assigned(CFExecutor) then
    CFExecutor := TExecutor.Create;
  Result := CFExecutor;
end;

class function TDefaultExecutor.UnhandledCount: SizeInt;
begin
  if Assigned(CFExecutor) then
    Result := CFExecutor.Unhandled
  else
    Result := 0;
end;

{ TGBlockChannel }

function TGBlockChannel.GetWait: Boolean;
begin
  Result := LongBool(FWait);
end;

function TGBlockChannel.GetCapacity: SizeInt;
begin
  Result := FCapacity;
end;

procedure TGBlockChannel.SendData(constref aValue: T);
begin
  FQueue.Enqueue(aValue);
  System.RtlEventSetEvent(FReadAwait);
  if FQueue.Count < Capacity then
    System.RtlEventSetEvent(FWriteAwait);
end;

function TGBlockChannel.ReceiveData: T;
begin
  Result := FQueue.Dequeue;
  System.RtlEventSetEvent(FWriteAwait);
  if FQueue.Count > 0 then
    System.RtlEventSetEvent(FReadAwait);
end;

class function TGBlockChannel.CreateQueue(aCapacity: SizeInt): IQueue;
begin
  Result := specialize TGQueue<T>.Create(aCapacity);
end;

constructor TGBlockChannel.Create(aCapacity: SizeInt);
begin
  if aCapacity <= 0 then
    begin
      FQueue := CreateQueue(DEFAULT_CONTAINER_CAPACITY);
      FCapacity := CHAN_SIZE_UNBOUND;
    end
  else
    begin
      FCapacity := aCapacity;
      FQueue := CreateQueue(aCapacity);
    end;
  FActive := True;
  System.InitCriticalSection(FLock);
end;

destructor TGBlockChannel.Destroy;
begin
  Close;
  System.EnterCriticalSection(FLock);
  try
    FQueue._GetRef.Free;
    System.RtlEventDestroy(FWriteAwait);
    FWriteAwait := nil;
    System.RtlEventDestroy(FReadAwait);
    FReadAwait := nil;
    inherited;
  finally
    System.LeaveCriticalSection(FLock);
    System.DoneCriticalSection(FLock);
  end;
end;

procedure TGBlockChannel.AfterConstruction;
begin
  inherited;
  FWriteAwait := System.RtlEventCreate;
  FReadAwait  := System.RtlEventCreate;
  System.RtlEventSetEvent(FWriteAwait);
end;

function TGBlockChannel.Send(constref aValue: T): Boolean;
begin
  System.RtlEventWaitFor(FWriteAwait);
  System.EnterCriticalSection(FLock);
  try
    Result := Active;
    if Result then
      SendData(aValue)
    else
      System.RtlEventSetEvent(FWriteAwait);
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

function TGBlockChannel.TrySend(constref aValue: T): Boolean;
begin
  System.EnterCriticalSection(FLock);
  try
    Result := False;
    if Active and (FQueue.Count < Capacity) then
      begin
        SendData(aValue);
        Result := True;
      end;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

function TGBlockChannel.Receive(out aValue: T): Boolean;
begin
  InterlockedIncrement(FWait);
  System.RtlEventWaitFor(FReadAwait);
  System.EnterCriticalSection(FLock);
  try
    InterlockedDecrement(FWait);
    Result := Active;
    if Result then
      aValue := ReceiveData
    else
      System.RtlEventSetEvent(FReadAwait);
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

function TGBlockChannel.TryReceive(out aValue: T): Boolean;
begin
  System.EnterCriticalSection(FLock);
  try
    Result := False;
    if Active and (FQueue.Count > 0) then
      begin
        aValue := ReceiveData;
        Result := True;
      end
    else
      Result := False;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

function TGBlockChannel.Peek: SizeInt;
begin
  System.EnterCriticalSection(FLock);
  try
    if Active then
      Result := FQueue.Count
    else
      Result := NULL_INDEX;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TGBlockChannel.Close;
begin
  System.EnterCriticalSection(FLock);
  try
    if Active then
      begin
        FActive := False;
        System.RtlEventSetEvent(FReadAwait);
        System.RtlEventSetEvent(FWriteAwait);
      end;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TGBlockChannel.Open;
begin
  System.EnterCriticalSection(FLock);
  try
    if not Active then
      begin
        FActive := True;
        if FQueue.Count > 0 then
          System.RtlEventSetEvent(FReadAwait);
        if FQueue.Count < Capacity then
          System.RtlEventSetEvent(FWriteAwait);
      end;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

{ TGPrioBlockChannel }

class function TGPrioBlockChannel.CreateQueue(aCapacity: SizeInt): IQueue;
begin
  Result := specialize TGBaseBinHeap<T, TCmpRel>.Create(aCapacity);
end;

{ TGObjBlockChannel }

function TGObjBlockChannel.GetOwnsObjects: Boolean;
begin
  Result := TQueue(FQueue._GetRef).OwnsObjects;
end;

procedure TGObjBlockChannel.SetOwnsObjects(aValue: Boolean);
begin
  TQueue(FQueue._GetRef).OwnsObjects := aValue;
end;

class function TGObjBlockChannel.CreateQueue(aCapacity: SizeInt): IQueue;
begin
  Result := TQueue.Create(aCapacity);
end;

constructor TGObjBlockChannel.Create(aCapacity: SizeInt; aOwnsObjects: Boolean);
begin
  inherited Create(aCapacity);
  OwnsObjects := aOwnsObjects;
end;

{ TWorkThread }

function TWorkThread.GetThreadID: TThreadID;
begin
  Result := ThreadID;
end;

function TWorkThread.GetHandle: TThreadID;
begin
  Result := Handle;
end;

{ TGListenThread.TWorker }

procedure TGListenThread.TWorker.Execute;
var
  Message: T;
begin
  while not Terminated and FChannel.Receive(Message) do
    try
      FOwner.HandleMessage(Message, Self);
    except
      FOwner.HandleException(Message, Self, Exception(System.AcquireExceptionObject));
    end;
end;

constructor TGListenThread.TWorker.Create(aOwner: TGListenThread; aChannel: TChannel; aStackSize: SizeUInt);
begin
  inherited Create(True, aStackSize);
  FOwner := aOwner;
  FChannel := aChannel;
  FreeOnTerminate := True;
end;


{ TGListenThread }

function TGListenThread.GetCapacity: SizeInt;
begin
  Result := FChannel.Capacity;
end;

function TGListenThread.GetEnqueued: SizeInt;
begin
  Result := FChannel.Peek;
end;

function TGListenThread.GetPriority: TThreadPriority;
begin
  Result := tpIdle;
  if FWorker <> nil then
    Result := FWorker.Priority;
end;

procedure TGListenThread.SetPriority(aValue: TThreadPriority);
begin
  if FWorker <> nil then
    FWorker.Priority := aValue;
end;

function TGListenThread.GetThreadID: TThreadID;
begin
  Result := 0;
  if FWorker <> nil then
    Result := FWorker.ThreadID;
end;

function TGListenThread.GetHandle: TThreadID;
begin
  Result := 0;
  if FWorker <> nil then
    Result := FWorker.Handle;
end;

procedure TGListenThread.HandleException(constref aMsg: T; aThreed: IWorkThread; e: Exception);
begin
  ReleaseExceptionObject;
end;

class function TGListenThread.CreateChannel(aCapacity: SizeInt): TChannel;
begin
  Result := TChannel.Create(aCapacity);
end;

constructor TGListenThread.Create(aCapacity: SizeInt; aStackSize: SizeUInt);
begin
  FChannel := CreateChannel(aCapacity);
  FWorker := TWorker.Create(Self, FChannel, aStackSize);
end;

destructor TGListenThread.Destroy;
begin
  FWorker := nil;
  FChannel.Free;
  inherited;
end;

procedure TGListenThread.AfterConstruction;
begin
  inherited;
  FWorker.Start;
end;

procedure TGListenThread.BeforeDestruction;
begin
  FWorker.Terminate;
  FChannel.Close;
  inherited;
end;

procedure TGListenThread.Send(constref aMessage: T);
begin
  FChannel.Send(aMessage);
end;

function TGListenThread.TrySend(constref aMessage: T): Boolean;
begin
  Result := FChannel.TrySend(aMessage);
end;

{ TThreadPool.TWorker }

procedure TThreadPool.TWorker.Execute;
var
  CurrTask: ITask = nil;
begin
  while not Terminated and FChannel.Receive(CurrTask) do
    try
      CurrTask.Execute;
    except
      FOwner.HandleException(Self, Exception(System.AcquireExceptionObject));
    end;
end;

constructor TThreadPool.TWorker.Create(aOwner: TThreadPool; aChannel: TChannel; aStackSize: SizeUInt);
begin
  inherited Create(True, aStackSize);
  FOwner := aOwner;
  FChannel := aChannel;
end;

{ TThreadPool }

function TThreadPool.GetCapacity: SizeInt;
begin
  Result := FChannel.Capacity;
end;

function TThreadPool.GetEnqueued: SizeInt;
begin
  Result := FChannel.Peek;
end;

function TThreadPool.GetThreadCount: SizeInt;
begin
  System.EnterCriticalSection(FLock);
  try
    Result := FPool.Count;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TThreadPool.SetThreadCount(aValue: SizeInt);
begin
  System.EnterCriticalSection(FLock);
  try
    if aValue > FPool.Count then
      PoolGrow(aValue)
    else
      if aValue < FPool.Count then
        PoolShrink(aValue);
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TThreadPool.AddThread;
var
  I: SizeInt;
begin
  I := FPool.Add(TWorker.Create(Self, FChannel, FStackSize));
  FPool[I].Start;
end;

procedure TThreadPool.PoolGrow(aValue: SizeInt);
begin
  while FPool.Count < aValue do
    AddThread;
end;

procedure TThreadPool.PoolShrink(aValue: SizeInt);
begin
  if aValue < 1 then
    aValue := 1;
  TerminatePool;
  FChannel.Open;
  PoolGrow(aValue);
end;

procedure TThreadPool.TerminatePool;
var
  Thread: TWorker;
begin
  for Thread in FPool.Reverse do
    Thread.Terminate;
  FChannel.Close;
  while FPool.NonEmpty do
    begin
      Thread := FPool.Extract(Pred(FPool.Count));
      Thread.WaitFor;
      Thread.Free;
    end;
end;

procedure TThreadPool.Lock;
begin
  System.EnterCriticalSection(FLock);
end;

procedure TThreadPool.Unlock;
begin
  System.LeaveCriticalSection(FLock);
end;

procedure TThreadPool.HandleException(aThreed: IWorkThread; e: Exception);
begin
  ReleaseExceptionObject;
  Assert(aThreed = aThreed);
  Assert(e = e);
end;

constructor TThreadPool.Create(aThreadCount: SizeInt; aQueueCapacity: SizeInt; aThreadStackSize: SizeUInt);
begin
  FStackSize := aThreadStackSize;
  FChannel := TChannel.Create(aQueueCapacity);
  if aThreadCount > 0 then
    PoolGrow(aThreadCount)
  else
    begin
      aThreadCount := TThread.ProcessorCount;
      PoolGrow(aThreadCount);
    end;
  System.InitCriticalSection(FLock);
end;

destructor TThreadPool.Destroy;
begin
  System.EnterCriticalSection(FLock);
  try
    TerminatePool;
    FPool.Clear;
    FChannel.Free;
    inherited;
  finally
    System.LeaveCriticalSection(FLock);
    System.DoneCriticalSection(FLock);
  end;
end;

procedure TThreadPool.EnsureThreadCount(aValue: SizeInt);
begin
  System.EnterCriticalSection(FLock);
  try
    if aValue > FPool.Count then
      PoolGrow(aValue)
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TThreadPool.EnqueueTask(aTask: ITask);
begin
  FChannel.Send(aTask);
end;

function TThreadPool.TryEnqueueTask(aTask: ITask): Boolean;
begin
  Result := FChannel.TrySend(aTask);
end;

{ TPrioThreadPool.TWorker }

procedure TPrioThreadPool.TWorker.Execute;
var
  CurrTask: IPriorityTask = nil;
begin
  while not Terminated and FChannel.Receive(CurrTask) do
    try
      CurrTask.Execute;
    except
      FOwner.HandleException(Self, Exception(System.AcquireExceptionObject));
    end;
end;

constructor TPrioThreadPool.TWorker.Create(aOwner: TPrioThreadPool; aChannel: TChannel; aStackSize: SizeUInt);
begin
  inherited Create(True, aStackSize);
  FOwner := aOwner;
  FChannel := aChannel;
end;

{ TPrioThreadPool }

function TPrioThreadPool.GetCapacity: SizeInt;
begin
  Result := FChannel.Capacity;
end;

function TPrioThreadPool.GetEnqueued: SizeInt;
begin
  Result := FChannel.Peek;
end;

function TPrioThreadPool.GetThreadCount: SizeInt;
begin
  System.EnterCriticalSection(FLock);
  try
    Result := FPool.Count;
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TPrioThreadPool.SetThreadCount(aValue: SizeInt);
begin
  System.EnterCriticalSection(FLock);
  try
    if aValue > FPool.Count then
      PoolGrow(aValue)
    else
      if aValue < FPool.Count then
        PoolShrink(aValue);
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TPrioThreadPool.AddThread;
var
  I: SizeInt;
begin
  I := FPool.Add(TWorker.Create(Self, FChannel, FStackSize));
  FPool[I].Start;
end;

procedure TPrioThreadPool.PoolGrow(aValue: SizeInt);
begin
  while FPool.Count < aValue do
    AddThread;
end;

procedure TPrioThreadPool.PoolShrink(aValue: SizeInt);
begin
  if aValue < 1 then
    aValue := 1;
  TerminatePool;
  FChannel.Open;
  PoolGrow(aValue);
end;

procedure TPrioThreadPool.TerminatePool;
var
  Thread: TWorker;
begin
  for Thread in FPool.Reverse do
    Thread.Terminate;
  FChannel.Close;
  while FPool.NonEmpty do
    begin
      Thread := FPool.Extract(Pred(FPool.Count));
      Thread.WaitFor;
      Thread.Free;
    end;
end;

procedure TPrioThreadPool.Lock;
begin
  System.EnterCriticalSection(FLock);
end;

procedure TPrioThreadPool.Unlock;
begin
  System.LeaveCriticalSection(FLock);
end;

procedure TPrioThreadPool.HandleException(aThreed: IWorkThread; e: Exception);
begin
  ReleaseExceptionObject;
  Assert(aThreed = aThreed);
  Assert(e = e);
end;

constructor TPrioThreadPool.Create(aThreadCount: SizeInt; aQueueCapacity: SizeInt; aThreadStackSize: SizeUInt);
begin
  FStackSize := aThreadStackSize;
  FChannel := TChannel.Create(aQueueCapacity);
  if aThreadCount > 0 then
    PoolGrow(aThreadCount)
  else
    begin
      aThreadCount := TThread.ProcessorCount;
      PoolGrow(aThreadCount);
    end;
  System.InitCriticalSection(FLock);
end;

destructor TPrioThreadPool.Destroy;
begin
  System.EnterCriticalSection(FLock);
  try
    TerminatePool;
    FPool.Clear;
    FChannel.Free;
    inherited;
  finally
    System.LeaveCriticalSection(FLock);
    System.DoneCriticalSection(FLock);
  end;
end;

procedure TPrioThreadPool.EnsureThreadCount(aValue: SizeInt);
begin
  System.EnterCriticalSection(FLock);
  try
    if aValue > FPool.Count then
      PoolGrow(aValue)
  finally
    System.LeaveCriticalSection(FLock);
  end;
end;

procedure TPrioThreadPool.EnqueueTask(aTask: IPriorityTask);
begin
  FChannel.Send(aTask);
end;

function TPrioThreadPool.TryEnqueueTask(aTask: IPriorityTask): Boolean;
begin
  Result := FChannel.TrySend(aTask);
end;

end.
