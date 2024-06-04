UNIT Decimate;

{=============================================================================================================
   Gabriel Moraru
   2024.05

   This is a port (but contains also major reworks) from C to Delphi.
   The original C code can be downloaded from http://tdistler.com/iqa
--------------------------------------------------------------------------------------------------------------
  Downsamples (decimates) an image.

  Params:
     img        Image to modify
     ImgWidth   Image width
     ImgHeigth  Image height
     factor     Decimation factor
     k          The kernel to apply (e.g. low-pass filter). Can be 0.
     Rez        Buffer to hold the resulting image (w/factor*ImgHeigth/factor). If 0, the result will be written to the original image buffer.
     rw rh      Optional. The width/height  of the resulting image will be stored here.
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES System.SysUtils, SsimDef;

procedure DecimateImage(img: RealImage; ImgWidth, ImgHeigth: integer; factor: integer; k: TKernelAttrib; Rez: RealImage; OUT rw, rh: Integer);

IMPLEMENTATION

USES Convolve;


procedure DecimateImage(img: RealImage; ImgWidth, ImgHeigth: integer;  factor: integer; k: TKernelAttrib; Rez: RealImage; OUT rw, rh: Integer);
var
   x, y: integer;
   sw, sh: Integer;
   dst_offset: integer;
   dst: RealImage;
begin
  // test oddity
  sw:= ImgWidth DIV factor;
  if Odd(sw) then Inc(sw);

  sh:= ImgHeigth DIV factor;
  if Odd(sh) then Inc(sh);

  dst:= img;
  if rez <> NIL
  then dst:= Rez;

  // Downsample
  for y:= 0 to sh-1 do
   begin
    dst_offset:= y * sw;
    Assert(dst_offset < Length(dst), 'Invalid dst!');

    for x:= 0 to sw-1  do
      begin
       Assert(x*factor < {=} ImgWidth, 'x:'+ IntToStr(x)+ '.  factor:'+ IntToStr(factor)+ '.  w:'+ IntToStr(ImgWidth)); // here was:  x*factor < w

       dst[dst_offset]:= FilterPixel(img, ImgWidth, ImgHeigth, x*factor, y*factor, k, 1);
       Inc(dst_offset);
      end;
   end;

  rw:= sw;
  rh:= sh;
end;

end.
