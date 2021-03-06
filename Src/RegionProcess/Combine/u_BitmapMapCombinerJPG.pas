{******************************************************************************}
{* SAS.Planet (SAS.�������)                                                   *}
{* Copyright (C) 2007-2014, SAS.Planet development team.                      *}
{* This program is free software: you can redistribute it and/or modify       *}
{* it under the terms of the GNU General Public License as published by       *}
{* the Free Software Foundation, either version 3 of the License, or          *}
{* (at your option) any later version.                                        *}
{*                                                                            *}
{* This program is distributed in the hope that it will be useful,            *}
{* but WITHOUT ANY WARRANTY; without even the implied warranty of             *}
{* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *}
{* GNU General Public License for more details.                               *}
{*                                                                            *}
{* You should have received a copy of the GNU General Public License          *}
{* along with this program.  If not, see <http://www.gnu.org/licenses/>.      *}
{*                                                                            *}
{* http://sasgis.org                                                          *}
{* info@sasgis.org                                                            *}
{******************************************************************************}

unit u_BitmapMapCombinerJPG;

interface

uses
  Types,
  SysUtils,
  Classes,
  LibJpegWrite,
  i_NotifierOperation,
  i_Projection,
  i_BitmapTileProvider,
  i_ImageLineProvider,
  i_BitmapMapCombiner,
  u_BaseInterfacedObject;

type
  TBitmapMapCombinerJPG = class(TBaseInterfacedObject, IBitmapMapCombiner)
  private
    FProgressUpdate: IBitmapCombineProgressUpdate;
    FWidth: Integer;
    FHeight: Integer;
    FQuality: Integer;
    FLineProvider: IImageLineProvider;
    FSaveGeoRefInfoToExif: Boolean;
    FOperationID: Integer;
    FCancelNotifier: INotifierOperation;
    function GetLine(
      Sender: TObject;
      ALineNumber: Integer;
      ALineSize: Cardinal;
      out Abort: Boolean
    ): PByte;
  private
    procedure SaveRect(
      AOperationID: Integer;
      const ACancelNotifier: INotifierOperation;
      const AFileName: string;
      const AImageProvider: IBitmapTileProvider;
      const AMapRect: TRect
    );
  public
    constructor Create(
      const AProgressUpdate: IBitmapCombineProgressUpdate;
      const AQuality: Integer;
      const ASaveGeoRefInfoToExif: Boolean
    );
  end;

implementation

uses
  Exif,
  t_GeoTypes,
  u_ImageLineProvider,
  u_GeoFunc,
  u_ResStrings;

{ TThreadMapCombineJPG }

constructor TBitmapMapCombinerJPG.Create(
  const AProgressUpdate: IBitmapCombineProgressUpdate;
  const AQuality: Integer;
  const ASaveGeoRefInfoToExif: Boolean
);
begin
  inherited Create;
  FProgressUpdate := AProgressUpdate;
  FQuality := AQuality;
  FSaveGeoRefInfoToExif := ASaveGeoRefInfoToExif;
end;

procedure TBitmapMapCombinerJPG.SaveRect(
  AOperationID: Integer;
  const ACancelNotifier: INotifierOperation;
  const AFileName: string;
  const AImageProvider: IBitmapTileProvider;
  const AMapRect: TRect
);
const
  JPG_MAX_HEIGHT = 65536;
  JPG_MAX_WIDTH = 65536;
var
  VJpegWriter: TJpegWriter;
  VStream: TFileStream;
  VCurrentPieceRect: TRect;
  VProjection: IProjection;
  VMapPieceSize: TPoint;
  VExif: TExifSimple;
  VCenterLonLat: TDoublePoint;
  VUseBGRAColorSpace: Boolean;
begin
  FOperationID := AOperationID;
  FCancelNotifier := ACancelNotifier;

  VProjection := AImageProvider.Projection;
  VCurrentPieceRect := AMapRect;
  VMapPieceSize := RectSize(VCurrentPieceRect);

  VUseBGRAColorSpace := True; // Available for libjpeg-turbo only

  if VUseBGRAColorSpace then begin
    FLineProvider :=
      TImageLineProviderBGRA.Create(
        AImageProvider,
        AMapRect
      );
  end else begin
    FLineProvider :=
      TImageLineProviderRGB.Create(
        AImageProvider,
        AMapRect
      );
  end;

  FWidth := VMapPieceSize.X;
  FHeight := VMapPieceSize.Y;
  if (FWidth >= JPG_MAX_WIDTH) or (FHeight >= JPG_MAX_HEIGHT) then begin
    raise Exception.CreateFmt(SAS_ERR_ImageIsTooBig, ['JPG', FWidth, JPG_MAX_WIDTH, FHeight, JPG_MAX_HEIGHT, 'JPG']);
  end;
  VStream := TFileStream.Create(AFileName, fmCreate);
  try
    VJpegWriter := TJpegWriter.Create(VStream, VUseBGRAColorSpace);
    try
      VJpegWriter.Width := FWidth;
      VJpegWriter.Height := FHeight;
      VJpegWriter.Quality := FQuality;
      VJpegWriter.AddCommentMarker('Created with SAS.Planet' + #0);
      if FSaveGeoRefInfoToExif then begin
        VCenterLonLat := VProjection.PixelPos2LonLat(CenterPoint(AMapRect));
        VExif := TExifSimple.Create(VCenterLonLat.Y, VCenterLonLat.X);
        try
          VJpegWriter.AddExifMarker(VExif.Stream);
        finally
          VExif.Free;
        end;
      end;
      VJpegWriter.Compress(Self.GetLine);
    finally
      VJpegWriter.Free;
    end;
  finally
    VStream.Free;
  end;
end;

function TBitmapMapCombinerJPG.GetLine(
  Sender: TObject;
  ALineNumber: Integer;
  ALineSize: Cardinal;
  out Abort: Boolean
): PByte;
begin
  if ALineNumber mod 256 = 0 then begin
    FProgressUpdate.Update(ALineNumber / FHeight);
  end;
  Result := FLineProvider.GetLine(FOperationID, FCancelNotifier, ALineNumber);
  Abort := (Result = nil) or FCancelNotifier.IsOperationCanceled(FOperationID);
end;

end.
