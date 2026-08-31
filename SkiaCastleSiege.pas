{*******************************************************************************
  Castle Siege (Catapult Physics Prototype)  v0.1
********************************************************************************
  Features:
  - Slingshot mechanics with pull-back aiming (Inverted drag)
  - Trajectory prediction overlay
  - Destructible cross-section castle walls with gravity support
  - Floating blocks fall down when underlying blocks are destroyed
  - Independent projectile physics (decoupled from catapult arm)
  - Big Victory Screen overlay when the King is hit
  - Automated level reset after 3 seconds of victory
  Built entirely with Skia4Delphi.
  Author:  Lara Miriam Tamy Reschke
  License: MIT
*******************************************************************************}
unit SkiaCastleSiege;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math,
  System.Generics.Collections, System.UITypes, System.SyncObjs, FMX.Types,
  FMX.Controls, FMX.Forms, FMX.Skia, System.Skia, Winapi.Windows;

const
  GRAVITY = 900;
  CELL_SIZE = 10;
  EXPLOSION_RADIUS = 40;
  ARM_LENGTH = 60;

type
  TParticle = record
    Pos: TPointF;
    Vel: TPointF;
    Life: Single;
    Color: TAlphaColor;
    Size: Single;
  end;

  TWallCell = record
    X, Y: Integer;
    Exists: Boolean;
    VelY: Single;
    IsFalling: Boolean;
  end;

  TCastleSiege = class(TSkCustomControl)
  private
    FThread: TThread;
    FActive: Boolean;
    FLock: TCriticalSection;
    FCatapultPos: TPointF;
    FProjectilePos: TPointF;
    FProjectileVel: TPointF;
    FIsFlying: Boolean;
    FIsShooting: Boolean;
    FLevelInitialized: Boolean;
    FAnimPhase: Single;
    FArmAnim: Single;
    FArmReturning: Boolean;
    FDragStart: TPointF;
    FIsAiming: Boolean;
    FWall: TList<TWallCell>;
    FParticles: TList<TParticle>;
    FKingPos: TPointF;
    FScore: Integer;
    FTargetHit: Boolean;
    FTargetResetTimer: Single;
    FAimDrag: TPointF;
    procedure InitLevel;
    procedure FireProjectile;
    procedure Explode(X, Y: Single; HitTarget: Boolean);
    procedure DoPhysicsUpdate(DeltaSec: Double);
    procedure SafeInvalidate;
    procedure StartThread;
    procedure StopThread;
    procedure SpawnParticles(X, Y: Single; Color: TAlphaColor; Count: Integer = 15);
    procedure DrawBackground(const ACanvas: ISkCanvas);
    procedure DrawCatapult(const ACanvas: ISkCanvas);
    procedure DrawAimGuide(const ACanvas: ISkCanvas);
    procedure DrawProjectile(const ACanvas: ISkCanvas);
    procedure DrawTarget(const ACanvas: ISkCanvas);
    procedure DrawWall(const ACanvas: ISkCanvas);
    procedure DrawParticles(const ACanvas: ISkCanvas);
    procedure DrawUI(const ACanvas: ISkCanvas);
    procedure DrawVictoryScreen(const ACanvas: ISkCanvas);
    function IsKeyDown(Key: Integer): Boolean;
    function GetBucketPos: TPointF;
  protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation
{ TCastleSiege }

function TCastleSiege.IsKeyDown(Key: Integer): Boolean;
begin
  Result := (GetAsyncKeyState(Key) and $8000) <> 0;
end;

constructor TCastleSiege.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;
  FActive := True;
  FLevelInitialized := False;
  FParticles := TList<TParticle>.Create;
  FWall := TList<TWallCell>.Create;
  FScore := 0;
  FAnimPhase := 0;
  FArmAnim := 0;
  FArmReturning := False;
  FTargetHit := False;
  FTargetResetTimer := 0;
  StartThread;
end;

destructor TCastleSiege.Destroy;
begin
  StopThread;
  FreeAndNil(FParticles);
  FreeAndNil(FWall);
  FreeAndNil(FLock);
  inherited;
end;

procedure TCastleSiege.Resize;
begin
  inherited;
  if (Width > 0) and (Height > 0) and not FLevelInitialized then
  begin
    InitLevel;
    FLevelInitialized := True;
  end;
end;

function TCastleSiege.GetBucketPos: TPointF;
var
  PivotX, PivotY: Single;
  BaseAngle: Single;
begin
  PivotX := FCatapultPos.X;
  PivotY := FCatapultPos.Y;
  BaseAngle := -3 * Pi / 4; // -135 degrees (loaded position)
  Result.X := PivotX + Cos(BaseAngle + FArmAnim * Pi / 2) * ARM_LENGTH;
  Result.Y := PivotY + Sin(BaseAngle + FArmAnim * Pi / 2) * ARM_LENGTH;
end;

procedure TCastleSiege.InitLevel;
var
  BaseX, BaseY: Single;
  R, C: Integer;
  Cell: TWallCell;
  TowerHeight, WallHeight: Integer;
  Gap: Boolean;
  KingRoomX: Integer;
begin
  FCatapultPos := PointF(150, Height - 80);
  FProjectilePos := GetBucketPos;
  FProjectileVel := TPointF.Zero;
  FIsFlying := False;
  FIsShooting := False;
  FArmAnim := 0;
  FArmReturning := False;
  FWall.Clear;
  BaseX := Width - 350;
  BaseY := Height - 80;
  for C := 0 to 24 do
  begin
    Gap := (C mod 3) = 2;
    if (C = 0) or (C = 24) then
      WallHeight := 18
    else if (C = 12) then
      WallHeight := 14
    else if Gap then
      WallHeight := 4
    else
      WallHeight := 10;
    for R := 0 to WallHeight - 1 do
    begin
      if (Gap and (R > 4)) then
        Continue;
      if (not Gap and (C > 0) and (C < 24) and (R = 6) and ((C mod 2) = 0)) then
        Continue;
      Cell.X := Trunc(BaseX + (C * CELL_SIZE));
      Cell.Y := Trunc(BaseY - (R * CELL_SIZE) - CELL_SIZE);
      Cell.Exists := True;
      Cell.VelY := 0;
      Cell.IsFalling := False;
      FWall.Add(Cell);
    end;
    if not Gap then
    begin
      Cell.X := Trunc(BaseX + (C * CELL_SIZE));
      Cell.Y := Trunc(BaseY - (WallHeight * CELL_SIZE) - CELL_SIZE);
      Cell.Exists := True;
      Cell.VelY := 0;
      Cell.IsFalling := False;
      FWall.Add(Cell);
    end;
  end;
  KingRoomX := Trunc(BaseX + (18 * CELL_SIZE));
  FKingPos := PointF(KingRoomX, BaseY - 30);
end;

procedure TCastleSiege.FireProjectile;
begin
  // Triggers both the independent projectile flight and the catapult arm swing
  FIsFlying := True;
  FIsShooting := True;
end;

procedure TCastleSiege.Explode(X, Y: Single; HitTarget: Boolean);
var
  I: Integer;
  Cell: TWallCell;
  DX, DY, Dist: Single;
begin
  // Spawn visual impact particles
  SpawnParticles(X, Y, $FFFF0000, 30);
  SpawnParticles(X, Y, $FF8B0000, 20);
  if not HitTarget then
  begin
    SpawnParticles(X, Y, $FFA0A0A0, 30);
    SpawnParticles(X, Y, $FF707070, 20);
  end;
  // Destroy wall cells within the explosion radius
  for I := FWall.Count - 1 downto 0 do
  begin
    Cell := FWall[I];
    DX := (Cell.X + CELL_SIZE / 2) - X;
    DY := (Cell.Y + CELL_SIZE / 2) - Y;
    Dist := Hypot(DX, DY);
    if Dist < EXPLOSION_RADIUS then
      FWall.Delete(I);
  end;
end;

procedure TCastleSiege.SpawnParticles(X, Y: Single; Color: TAlphaColor; Count: Integer = 15);
var
  I: Integer;
  P: TParticle;
begin
  // Generate random particles for explosion effects
  for I := 0 to Count - 1 do
  begin
    P.Pos := PointF(X, Y);
    P.Vel := PointF((Random - 0.5) * 600, (Random - 0.5) * 600 - 200);
    P.Life := 1.0;
    P.Color := Color;
    P.Size := 3 + Random * 5;
    FParticles.Add(P);
  end;
end;

procedure TCastleSiege.DoPhysicsUpdate(DeltaSec: Double);
var
  I, J: Integer;
  P: TParticle;
  GroundY: Single;
  Cell, BelowCell: TWallCell;
  DX, DY: Single;
  HitTarget, HasCollided: Boolean;
  Rad: Single;
  HasSupport: Boolean;
begin
  if not FActive or not FLevelInitialized then
    Exit;
  GroundY := Height - 80;
  FAnimPhase := FAnimPhase + DeltaSec;

  // Update Particles
  for I := FParticles.Count - 1 downto 0 do
  begin
    P := FParticles[I];
    P.Pos := P.Pos + TPointF.Create(P.Vel.X * DeltaSec, P.Vel.Y * DeltaSec);
    P.Vel.Y := P.Vel.Y + 800 * DeltaSec;
    P.Life := P.Life - DeltaSec * 1.5;
    if P.Life <= 0 then
      FParticles.Delete(I)
    else
      FParticles[I] := P;
  end;

  // Manual Reset
  if IsKeyDown(Ord('R')) then
  begin
    InitLevel;
    FTargetHit := False;
    Exit;
  end;

  // Victory state timer
  if FTargetHit then
  begin
    FTargetResetTimer := FTargetResetTimer - DeltaSec;
    if FTargetResetTimer <= 0 then
    begin
      InitLevel;
      FTargetHit := False;
    end;
    Exit;
  end;

  // 1. Catapult Arm Animation (Completely independent of the projectile)
  if FIsShooting or FArmReturning then
  begin
    if FArmReturning then
    begin
      FArmAnim := Max(0, FArmAnim - DeltaSec * 4);
      if FArmAnim <= 0 then
      begin
        FArmReturning := False;
        FIsShooting := False;
      end;
    end
    else
    begin
      FArmAnim := Min(1, FArmAnim + DeltaSec * 5);
      if FArmAnim >= 1 then
        FArmReturning := True;
    end;
  end;

  // Keep projectile attached to the arm if not flying or shooting
  if not FIsFlying and not FIsShooting and not FIsAiming then
    FProjectilePos := GetBucketPos;

  // 2. Projectile Physics (100% independent flight path)
  if FIsFlying then
  begin
    Rad := 12.0;

    FProjectileVel.Y := FProjectileVel.Y + GRAVITY * DeltaSec;
    FProjectilePos := FProjectilePos + TPointF.Create(FProjectileVel.X * DeltaSec, FProjectileVel.Y * DeltaSec);

    HitTarget := False;
    HasCollided := False;

    // Check Collision with King
    DX := FProjectilePos.X - FKingPos.X;
    DY := FProjectilePos.Y - FKingPos.Y;
    if (Abs(DX) < 15 + Rad) and (Abs(DY) < 30 + Rad) then
    begin
      HitTarget := True;
      HasCollided := True;
    end;

    // Check Collision with Walls
    if not HasCollided then
    begin
      for Cell in FWall do
      begin
        if not Cell.IsFalling then
        begin
          DX := FProjectilePos.X - (Cell.X + CELL_SIZE / 2);
          DY := FProjectilePos.Y - (Cell.Y + CELL_SIZE / 2);
          if (Abs(DX) < (CELL_SIZE / 2 + Rad)) and (Abs(DY) < (CELL_SIZE / 2 + Rad)) then
          begin
            HasCollided := True;
            Break;
          end;
        end;
      end;
    end;

    // Handle Impacts
    if HasCollided or (FProjectilePos.Y + Rad > GroundY) or (FProjectilePos.X > Width) or (FProjectilePos.X < 0) then
    begin
      Explode(FProjectilePos.X, FProjectilePos.Y, HitTarget);
      if HitTarget then
      begin
        Inc(FScore, 100);
        FTargetHit := True;
        FTargetResetTimer := 3.0; // 3 seconds victory screen
      end;
      FProjectileVel := TPointF.Zero;
      FIsFlying := False;
      if not FArmReturning then
        FArmReturning := True;
      if (FArmAnim = 0) then
        FProjectilePos := GetBucketPos;
    end;
  end;

  // 3. Wall Physics (Falling blocks)
  for I := 0 to FWall.Count - 1 do
  begin
    Cell := FWall[I];
    if not Cell.IsFalling then
    begin
      HasSupport := False;
      if Cell.Y + CELL_SIZE >= Trunc(GroundY) then
        HasSupport := True
      else
      begin
        for J := 0 to FWall.Count - 1 do
        begin
          if I = J then
            Continue;
          BelowCell := FWall[J];
          if not BelowCell.IsFalling and (BelowCell.Y = Cell.Y + CELL_SIZE) and (BelowCell.X = Cell.X) then
          begin
            HasSupport := True;
            Break;
          end;
        end;
      end;
      if not HasSupport then
      begin
        Cell.IsFalling := True;
        Cell.VelY := 0;
      end;
    end;
    if Cell.IsFalling then
    begin
      Cell.VelY := Cell.VelY + GRAVITY * DeltaSec;
      Cell.Y := Trunc(Cell.Y + Cell.VelY * DeltaSec);
      if Cell.Y + CELL_SIZE >= Trunc(GroundY) then
      begin
        Cell.Y := Trunc(GroundY) - CELL_SIZE;
        Cell.VelY := 0;
        Cell.IsFalling := False;
      end
      else
      begin
        for J := 0 to FWall.Count - 1 do
        begin
          if I = J then
            Continue;
          BelowCell := FWall[J];
          if not BelowCell.IsFalling and (BelowCell.Y = Cell.Y + CELL_SIZE) and (BelowCell.X = Cell.X) then
          begin
            Cell.VelY := 0;
            Cell.IsFalling := False;
            Cell.Y := BelowCell.Y - CELL_SIZE;
            Break;
          end;
        end;
      end;
    end;
    FWall[I] := Cell;
  end;
end;

procedure TCastleSiege.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    if not FIsFlying and not FTargetHit and not FIsShooting then
    begin
      FIsAiming := True;
      FDragStart := PointF(X, Y);
      FAimDrag := TPointF.Zero;
    end;
  end;
  inherited;
end;

procedure TCastleSiege.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  if FIsAiming then
  begin
    FAimDrag.X := X - FDragStart.X;
    FAimDrag.Y := Y - FDragStart.Y;
  end;
  inherited;
end;

procedure TCastleSiege.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if FIsAiming then
  begin
    FIsAiming := False;
    if (Abs(FAimDrag.X) > 20) or (Abs(FAimDrag.Y) > 20) then
    begin
      // Calculate inverted velocity based on drag distance
      FProjectileVel.X := -FAimDrag.X * 6;
      FProjectileVel.Y := -FAimDrag.Y * 6;
      if FProjectileVel.X > 2500 then
        FProjectileVel.X := 2500;
      if FProjectileVel.Y < -2500 then
        FProjectileVel.Y := -2500;
      FireProjectile;
    end;
    FAimDrag := TPointF.Zero;
  end;
  inherited;
end;

procedure TCastleSiege.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  if KeyChar = 'R' then
  begin
    InitLevel;
    FTargetHit := False;
    Key := 0;
  end;
  inherited;
end;

procedure TCastleSiege.Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
begin
  DrawBackground(ACanvas);
  if FLevelInitialized then
  begin
    DrawWall(ACanvas);
    DrawTarget(ACanvas);
    DrawCatapult(ACanvas);
    if FIsAiming then
      DrawAimGuide(ACanvas);
    DrawProjectile(ACanvas);
    DrawParticles(ACanvas);
  end;
  DrawUI(ACanvas);
  if FTargetHit then
    DrawVictoryScreen(ACanvas);
end;

procedure TCastleSiege.DrawBackground(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  PB: ISkPathBuilder;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.Color := $FF4A6D8C;
  ACanvas.DrawRect(TRectF.Create(0, 0, Width, Height), Paint);
  Paint.Color := $FF2D4A3E;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(0, Height - 80);
  PB.LineTo(Trunc(Width) div 2, Height - 320);
  PB.LineTo(Trunc(Width), Height - 80);
  ACanvas.DrawPath(PB.Snapshot, Paint);
  Paint.Color := $FF3E7C3E;
  ACanvas.DrawRect(TRectF.Create(0, Height - 80, Width, Height), Paint);
  Paint.Color := $FF2E5C2E;
  ACanvas.DrawRect(TRectF.Create(0, Height - 80, Width, Height - 75), Paint);
end;

procedure TCastleSiege.DrawCatapult(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  PB: ISkPathBuilder;
  PivotX, PivotY: Single;
  BaseAngle, CurrentAngle: Single;
  ArmEndX, ArmEndY: Single;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  PivotX := FCatapultPos.X;
  PivotY := FCatapultPos.Y;
  Paint.Color := $FF5A3A22;
  ACanvas.DrawCircle(PointF(PivotX - 30, PivotY + 20), 18, Paint);
  ACanvas.DrawCircle(PointF(PivotX + 30, PivotY + 20), 18, Paint);
  Paint.Color := $FF8B5A2B;
  ACanvas.DrawCircle(PointF(PivotX - 30, PivotY + 20), 8, Paint);
  ACanvas.DrawCircle(PointF(PivotX + 30, PivotY + 20), 8, Paint);
  Paint.Color := $FF6B4226;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(PivotX - 30, PivotY + 20);
  PB.LineTo(PivotX + 30, PivotY + 20);
  PB.LineTo(PivotX + 15, PivotY);
  PB.LineTo(PivotX - 15, PivotY);
  ACanvas.DrawPath(PB.Snapshot, Paint);

  BaseAngle := -3 * Pi / 4;
  CurrentAngle := BaseAngle + FArmAnim * Pi / 2;
  ArmEndX := PivotX + Cos(CurrentAngle) * ARM_LENGTH;
  ArmEndY := PivotY + Sin(CurrentAngle) * ARM_LENGTH;

  // Draw Arm
  Paint.Color := $FF8B5A2B;
  Paint.StrokeWidth := 8;
  Paint.Style := TSkPaintStyle.Stroke;
  ACanvas.DrawLine(PointF(PivotX, PivotY), PointF(ArmEndX, ArmEndY), Paint);

  // Draw flat bucket aligned exactly with the arm's angle
  ACanvas.Save;
  try
    ACanvas.Translate(ArmEndX, ArmEndY);
    ACanvas.Rotate(RadToDeg(CurrentAngle));

    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := $FF5A3A22;
    PB := TSkPathBuilder.Create;
    PB.MoveTo(-12, 0);
    PB.LineTo(12, 0);
    PB.LineTo(12, -8);
    PB.LineTo(-12, -8);
    ACanvas.DrawPath(PB.Snapshot, Paint);
  finally
    ACanvas.Restore;
  end;
end;

procedure TCastleSiege.DrawAimGuide(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  I: Integer;
  T, Px, Py, Vx, Vy: Single;
  Txt: string;
  Font: TSkFont;
  Origin: TPointF;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.Color := $FFFFFFFF;
  Paint.Alpha := 180;
  Origin := GetBucketPos;
  Vx := -FAimDrag.X * 6;
  Vy := -FAimDrag.Y * 6;
  if Vx > 2500 then
    Vx := 2500;
  if Vy < -2500 then
    Vy := -2500;
  for I := 1 to 60 do
  begin
    T := I * 0.05;
    Px := Origin.X + Vx * T;
    Py := Origin.Y + Vy * T + 0.5 * GRAVITY * T * T;
    if Py > Height - 80 then
      Break;
    if I mod 2 = 0 then
      ACanvas.DrawCircle(PointF(Px, Py), 3, Paint);
  end;
end;

procedure TCastleSiege.DrawProjectile(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  Pos: TPointF;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  if FIsFlying then
    Pos := FProjectilePos
  else
    Pos := GetBucketPos;
  Paint.Color := $FF333333;
  ACanvas.DrawCircle(Pos, 12, Paint);
  Paint.Color := $FF555555;
  ACanvas.DrawCircle(PointF(Pos.X + 4, Pos.Y - 4), 4, Paint);
end;

procedure TCastleSiege.DrawTarget(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  PB: ISkPathBuilder;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.Color := $FFD4AF37;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(FKingPos.X - 10, FKingPos.Y - 40);
  PB.LineTo(FKingPos.X - 10, FKingPos.Y - 50);
  PB.LineTo(FKingPos.X - 5, FKingPos.Y - 45);
  PB.LineTo(FKingPos.X, FKingPos.Y - 55);
  PB.LineTo(FKingPos.X + 5, FKingPos.Y - 45);
  PB.LineTo(FKingPos.X + 10, FKingPos.Y - 50);
  PB.LineTo(FKingPos.X + 10, FKingPos.Y - 40);
  ACanvas.DrawPath(PB.Snapshot, Paint);
  Paint.Color := $FF8B0000;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(FKingPos.X - 8, FKingPos.Y - 40);
  PB.LineTo(FKingPos.X + 8, FKingPos.Y - 40);
  PB.LineTo(FKingPos.X + 12, FKingPos.Y);
  PB.LineTo(FKingPos.X - 12, FKingPos.Y);
  ACanvas.DrawPath(PB.Snapshot, Paint);
end;

procedure TCastleSiege.DrawWall(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  Cell: TWallCell;
  Rect: TRectF;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := False;
  for Cell in FWall do
  begin
    if Cell.Exists then
    begin
      Rect := TRectF.Create(Cell.X, Cell.Y, Cell.X + CELL_SIZE, Cell.Y + CELL_SIZE);
      Paint.Color := $FF777777;
      ACanvas.DrawRect(Rect, Paint);
      Rect.Inflate(-1, -1);
      Paint.Color := $FF999999;
      ACanvas.DrawRect(Rect, Paint);
    end;
  end;
end;

procedure TCastleSiege.DrawParticles(const ACanvas: ISkCanvas);
var
  P: TParticle;
  Paint: ISkPaint;
begin
  if FParticles.Count = 0 then
    Exit;
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 3.0);
  for P in FParticles do
  begin
    Paint.Color := P.Color;
    Paint.Alpha := Round(P.Life * 255);
    ACanvas.DrawCircle(P.Pos, P.Size * P.Life, Paint);
  end;
end;

procedure TCastleSiege.DrawUI(const ACanvas: ISkCanvas);
var
  Font: TSkFont;
  Paint: ISkPaint;
  Txt: string;
begin
  Font := TSkFont.Create;
  try
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Fill;
    Paint.AntiAlias := True;
    Txt := 'Score: ' + IntToStr(FScore) + '  (Press R to Reset Level)';
    Paint.Color := TAlphaColors.White;
    ACanvas.DrawSimpleText(Txt, 20, 40, Font, Paint);
    if FTargetHit then
    begin
      Txt := 'King Defeated! Resetting...';
      Paint.Color := TAlphaColors.Lime;
    end
    else if FIsAiming then
    begin
      Txt := 'Pull back and release to FIRE!';
      Paint.Color := TAlphaColors.Yellow;
    end
    else
    begin
      Txt := 'Hold Left Mouse to aim';
      Paint.Color := TAlphaColors.White;
    end;
    ACanvas.DrawSimpleText(Txt, 20, 70, Font, Paint);
  finally
    Font.Free;
  end;
end;

procedure TCastleSiege.DrawVictoryScreen(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  FontLarge, FontSmall: TSkFont;
  Txt: string;
  TextWidth: Single;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  // Dim background
  Paint.Color := $80000000;
  ACanvas.DrawRect(TRectF.Create(0, 0, Width, Height), Paint);

  // Create fonts with specific sizes via constructor
  FontLarge := TSkFont.Create(nil, 64);
  FontSmall := TSkFont.Create(nil, 24);
  try
    // Draw "VICTORY!"
    Paint.Color := TAlphaColors.Yellow;
    Txt := 'VICTORY!';

    // Safe approximation for text width (Length * FontSize * 0.6 factor)
    TextWidth := Length(Txt) * 64 * 0.6;
    ACanvas.DrawSimpleText(Txt, (Width - TextWidth) / 2, Height / 2, FontLarge, Paint);

    // Draw "Level is resetting..."
    Paint.Color := TAlphaColors.White;
    Txt := 'Level is resetting...';

    TextWidth := Length(Txt) * 24 * 0.55;
    ACanvas.DrawSimpleText(Txt, (Width - TextWidth) / 2, (Height / 2) + 50, FontSmall, Paint);
  finally
    FontLarge.Free;
    FontSmall.Free;
  end;
end;

procedure TCastleSiege.SafeInvalidate;
begin
  if csDestroying in ComponentState then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) and Assigned(Self) then
      begin
        Redraw;
        Repaint;
      end;
    end);
end;

procedure TCastleSiege.StartThread;
begin
  if Assigned(FThread) then
    Exit;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LastTime, NowTime, DeltaMS: Cardinal;
    begin
      LastTime := TThread.GetTickCount;
      while not TThread.CheckTerminated do
      begin
        NowTime := TThread.GetTickCount;
        DeltaMS := NowTime - LastTime;
        if DeltaMS = 0 then
          DeltaMS := 1;
        LastTime := NowTime;
        if FActive then
        begin
          DoPhysicsUpdate(DeltaMS / 1000);
          SafeInvalidate;
        end;
        Sleep(16);
      end;
    end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TCastleSiege.StopThread;
begin
  FActive := False;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(50);
  end;
end;

end.

