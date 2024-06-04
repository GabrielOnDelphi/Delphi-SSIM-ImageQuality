UNIT SsimDef;

{=============================================================================================================
   Gabriel Moraru
   2024.05

   This is a port (but contains also major reworks) from C to Delphi.
   The original C code can be downloaded from http://tdistler.com/iqa
--------------------------------------------------------------------------------------------------------------
  TYPE DEFINITIONS AND UTIL FUNCTIONS
-------------------------------------------------------------------------------------------------------------}

{About 'static' in C:
   Static defined local variables do not lose their value between function calls. In other words they are global variables, but scoped to the local function they are defined in.
   Static global variables are not visible outside of the C file they are defined in.
   Static functions are not visible outside of the C file they are defined in.  }


INTERFACE
USES
    System.SysUtils, Vcl.Graphics;

CONST
   GAUSSIAN_LEN = 11;
   SQUARE_LEN = 8;                 { Equal weight square window. Each pixel is equally weighted (1/64) so that SUM(x) = 1.0 }

TYPE
  ByteImage = array of Byte;         // Unidimensional array (of size Width*Height) that holds the pixels of an image. Only gray images allowed on input.
  RealImage = array of Single;

TYPE
  TKernelWndType = (gwGaussian, gwSquare);  // gwSquare aka Linear. in orig code, gwGaussian is passed as 1 and gwSquare as 0 as parameters.

TYPE
  // Defines a convolution kernel
  TOutOfBoundsPredicate = reference to function (img: RealImage; w, ImgHeigth: integer; x, y: integer; bnd_const: single): Single;

  TKernelWindow= array of Single;

  TKernelAttrib = record              // was _kernel
     KernelW: TKernelWindow;          // Pointer to the kernel values
     Width, Height: integer;          // The kernel width/height
     Normalized: Boolean;             // true if the kernel values add up to 1
     bnd_opt: TOutOfBoundsPredicate;  // Defines how out-of-bounds image values are handled     _get_pixel
     bnd_const: single;               // If 'bnd_opt' is KBND_CONSTANT, this specifies the out-of-bounds value
   end;

TYPE
  TScaleFactor = (sfAuto, sfNone);
  TSsimArgs = record           // Allows fine-grain control of the SSIM algorithm.
    ScaleFactor: TScaleFactor; // was: 0=default scaling, 1=no scaling
    CustomParams: Boolean;    // If true, use custom alpha, beta, gamma, L, K1, K2. Otherwise, ignore then and use defaults
    Alpha: Single;             // luminance exponent
    Beta : single;             // contrast  exponent
    Gamma: single;             // structure exponent
    L : integer;               // dynamic range (2^8 - 1)
    K1: single;                // stabilization constant 1
    K2: single;                // stabilization constant 2
  public
    procedure Init;
  end;



procedure SetKernelWindow(VAR KernelAttrib: TKernelAttrib; KernelWnd: TKernelWndType);
function  TransferPixels (BMP: TBitmap): ByteImage;
procedure SetLengthAndZeroFill(VAR SomeArray: RealImage; Size: Integer);
function  GetStride(BMP: TBitmap): Integer;
function  RoundEx(CONST X: Extended): Longint;
procedure EmptyDummy;



IMPLEMENTATION


procedure TSsimArgs.Init;       { I tried 'constructor TSsimArgs.Create' but it doesn't work in XE7 }
begin
  CustomParams:= FALSE;
  ScaleFactor:= sfAuto;
  alpha := 1;
  beta  := 1;
  gamma := 1;
  L     := 255;
  K1    := 0.01;
  K2    := 0.03;
end;



{ If fractional part is >= 0.5 then the number is rounded up, else down. "Bank" algorithm example: Round(25.5) = 26 but Round(26.5) = 26 }
function RoundEx(CONST X: Extended): LongInt;
begin
 Result:= Trunc(x);
 if Frac(x) >= 0.50
 then Result:= Result+ 1;
end;


procedure SetKernelWindow(VAR KernelAttrib: TKernelAttrib; KernelWnd: TKernelWndType);
CONST
   { Circular-symmetric Gaussian weighting.
     h (x,y) = hg(x,y)/SUM(SUM(hg)), for normalization to 1
     hg(x,y) = e^( -0.5*( (x^2+y^2)/sigma^2 ) ), where sigma was 1.5 }
   g_gaussian_window: array [0..pred(GAUSSIAN_LEN*GAUSSIAN_LEN)] of single =
    (0.000001, 0.000008, 0.000037, 0.000112, 0.000219, 0.000274, 0.000219, 0.000112, 0.000037, 0.000008, 0.000001,
     0.000008, 0.000058, 0.000274, 0.000831, 0.001619, 0.002021, 0.001619, 0.000831, 0.000274, 0.000058, 0.000008,
     0.000037, 0.000274, 0.001296, 0.003937, 0.007668, 0.009577, 0.007668, 0.003937, 0.001296, 0.000274, 0.000037,
     0.000112, 0.000831, 0.003937, 0.011960, 0.023294, 0.029091, 0.023294, 0.011960, 0.003937, 0.000831, 0.000112,
     0.000219, 0.001619, 0.007668, 0.023294, 0.045371, 0.056662, 0.045371, 0.023294, 0.007668, 0.001619, 0.000219,
     0.000274, 0.002021, 0.009577, 0.029091, 0.056662, 0.070762, 0.056662, 0.029091, 0.009577, 0.002021, 0.000274,
     0.000219, 0.001619, 0.007668, 0.023294, 0.045371, 0.056662, 0.045371, 0.023294, 0.007668, 0.001619, 0.000219,
     0.000112, 0.000831, 0.003937, 0.011960, 0.023294, 0.029091, 0.023294, 0.011960, 0.003937, 0.000831, 0.000112,
     0.000037, 0.000274, 0.001296, 0.003937, 0.007668, 0.009577, 0.007668, 0.003937, 0.001296, 0.000274, 0.000037,
     0.000008, 0.000058, 0.000274, 0.000831, 0.001619, 0.002021, 0.001619, 0.000831, 0.000274, 0.000058, 0.000008,
     0.000001, 0.000008, 0.000037, 0.000112, 0.000219, 0.000274, 0.000219, 0.000112, 0.000037, 0.000008, 0.000001);
VAR i: Integer;
begin
  case KernelWnd of
    gwSquare:
        begin
          //square window
          SetLength(KernelAttrib.KernelW, SQUARE_LEN * SQUARE_LEN);
          KernelAttrib.width := SQUARE_LEN;
          KernelAttrib.Height := SQUARE_LEN;
          for i:= 0 to High(KernelAttrib.KernelW)
            DO KernelAttrib.KernelW[i]:= 0.015625;
        end;
    gwGaussian:
        begin
          // gaussian window;
          SetLength(KernelAttrib.KernelW, GAUSSIAN_LEN * GAUSSIAN_LEN);
          KernelAttrib.width  := GAUSSIAN_LEN;
          KernelAttrib.Height := GAUSSIAN_LEN;
          for i:= 0 to High(KernelAttrib.KernelW)
            DO KernelAttrib.KernelW[i]:= g_gaussian_window[i];
        end;
  end;
end;



{ Convert pixels to gray and transfer them from a TBitmap to a unidimensional array (of size Width*Height)
  x + 0 = Blue, x + 1 = Green, x + 2 = Red }
function TransferPixels(BMP: TBitmap): ByteImage;
TYPE
  { Scan line for pf32 images }
  TRGB32 = packed record
    B, G, R, A: Byte;
  end;
  TRGB32Array = packed array[0..MaxInt div SizeOf(TRGB32)-1] of TRGB32;  // some use MaxInt instead of MaxWord
  PRGB32Array = ^TRGB32Array;
VAR
   Target, cur, x, y: Integer;
   Line: PRGB32Array;
begin
 cur:= 0;
 BMP.PixelFormat:= pf32bit;
 SetLength(Result, BMP.Width * BMP.Height);
 for y := 0 to BMP.Height - 1 do
   begin
     Line := BMP.ScanLine[y];
     for x := 0 to BMP.Width - 1 do
       begin
        // Calculate a 'human-like' shade of gray
        Target:= RoundEx(
                  (0.30 * Line[x].r) +
                  (0.59 * Line[x].g) +
                  (0.11 * Line[x].b));
        Result[cur]:= Target;    // Fill gray pixels in the array
        Inc(cur);
       end;
   end;
end;


{  Stride is the length (in bytes) of each horizontal line in the image.
   This may be different from the image Width.
   http://paulbourke.net/dataformats/bitmaps/ }
function GetStride(BMP: TBitmap): integer;
VAR BytesPerPix: Integer;
begin
  //BytesPerPix := cGraphLoader.Resolution.GetBitsPerPixel(BMP);   // bits per pix
  //BytesPerPix := BytesPerPix DIV 8;                              // bytes per pix
  BytesPerPix := 1; // because I aways use gray!
  Result:= BMP.Width * BytesPerPix;
end;


procedure SetLengthAndZeroFill(VAR SomeArray: RealImage; Size: Integer);
begin
  SetLength(SomeArray, Size);
  FillChar(SomeArray[0], SizeOf(SomeArray), 0);
end;



procedure EmptyDummy;
begin
 //Sleep(1);
end;


end.

