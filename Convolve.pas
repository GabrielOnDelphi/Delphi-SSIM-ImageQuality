UNIT Convolve;

{-------------------------------------------------------------------------------------------------------------
  2019-08-17
  UnitTested: ok
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
   System.SysUtils, SsimDef;

// Applies the specified kernel to the image. The kernel will be applied to all areas where it fits completely within the image.
procedure ConvolveImage(img: RealImage; ImgWidth, ImgHeigth: integer; k: TKernelAttrib; Rez: RealImage; OUT rw,rh: integer);

// Returns the filtered version of the specified pixel. If no kernel is given, the raw pixel value is returned.
function  FilterPixel  (img: RealImage; ImgWidth, ImgHeigth: integer; PixelX, PixelY: integer; k: TKernelAttrib; kscale: single): Single;

// Predicate functions to process "Out of bound"
function KBND_SYMMETRIC(img: RealImage;  ImgWidth, ImgHeigth: integer;  x, y: integer;  bnd_const: single): Single;

IMPLEMENTATION




// Out-of-bounds array values are a mirrored reflection of the border values
function KBND_SYMMETRIC(img: RealImage;  ImgWidth, ImgHeigth: integer;  x, y: integer;  bnd_const: single): single;
begin
  if x < 0
  then x:= -1-x
  else
    if x >= ImgWidth
    then x:= (ImgWidth-(x-ImgWidth))-1;

  if y < 0
  then y:= -1-y
  else
    if y >= ImgHeigth
    then y:= (ImgHeigth-(y-ImgHeigth))-1;
      
  Result:= img[y*ImgWidth+x];
end;


// Out-of-bounds array values are set to the nearest border value
function KBND_REPLICATE(img: RealImage;  w, ImgHeigth: integer;  x,  y: integer;  bnd_const: single): single;  // unused
begin
  if x < 0  then x:= 0;
  if x >= w then x:= w-1;
  if y < 0  then y:= 0;
  if y >= ImgHeigth then y:= ImgHeigth-1;
 
  Result:= img[y*w+x];
end;


// Out-of-bounds array values are set to 'bnd_const'
function KBND_CONSTANT(img: RealImage;  w, ImgHeigth: integer;  x, y: integer;  bnd_const: single): single;  // unused
begin
  if x < 0 then x:= 0;
  if y < 0 then y:= 0;

  if (x>=w) OR (y>=ImgHeigth)
  then Result:= bnd_const
  else Result:= img[y*w+x];
end;


function ComputeScale(k: TKernelAttrib): single;
VAR
   ii: integer;
   k_len: integer;
   sum: single;
begin
  sum:=0;
  if k.normalized
  then Result:= 1
  else
    begin
      k_len:= k.Width * k.Height;
      for ii:=0 to Pred(k_len)
        DO sum:= sum + k.KernelW[ii];

      if sum<> 0
      then Result:= 1 / sum
      else Result:= 1
    end;
end;



{  Applies the specified kernel to the image.
   The kernel will be applied to all areas where it fits completely within the image.
   The resulting image will be smaller by half the kernel width and height (w - kw/2 and ImgHeigth - kh/2).

   Params:
      img Image to modify
      k The kernel to apply
      result
            Buffer to hold the resulting image ((w-kw)*(ImgHeigth-kh), where kw
             and kh are the kernel width and height). If 0, the result
             will be written to the original image buffer.
      rw Optional. The width of the resulting image will be stored here.
      rh Optional. The height of the resulting image will be stored here. }
procedure ConvolveImage(img: RealImage; ImgWidth, ImgHeigth: integer; k: TKernelAttrib; Rez: RealImage; OUT rw, rh: integer);
VAR
   PixelX, PixelY: integer;
   kx, ky: integer;
   u, v: integer;
   uc, vc: integer;
   kw_even, kh_even: integer;
   dst_w, dst_h: integer;
   ImgOffset: integer;
   KernOffset: integer;
   sum: Single;
   scale: Single;
   dst: RealImage;
begin
  if Length(k.KernelW)= 0                          //todo 5: make it an Assert
  then raise Exception.Create('KernelW is empty!');

  uc:= k.Width  DIV 2;
  vc:= k.Height DIV 2;

  if Odd(k.width)          //was  kw_even = (k->w&1)?0:1;
  then kw_even:= 0
  else kw_even:= 1;
  if Odd(k.Height)
  then kh_even:= 0
  else kh_even:= 1;

  dst_w:= ImgWidth  -k.width  +1;
  dst_h:= ImgHeigth -k.Height +1;
  dst:= Rez;                                //todo 2: get rid of 'dst' and work directly with Rez

  if dst = NIL
  then dst:= img;  // Convolve in-place

  { Kernel is applied to all positions where the kernel is fully contained in the image }
  scale:= ComputeScale(k);

  for PixelY:= 0 to dst_h-1 do
   for PixelX:= 0 to dst_w-1 do
     begin
      sum:= 0;
      KernOffset:= 0;
      ky:= PixelY+ vc;
      kx:= PixelX+ uc;
      for v:=-vc to vc-kh_even  do
       begin
        ImgOffset:= (ky + v)* ImgWidth + kx;

        for u := -uc to uc-kw_even do
         begin
           if ImgOffset + u < 0                                        //todo 5: make it an Assert
           then Exception.Create('Invalid ImgOffset!');

           if KernOffset >= Length(k.KernelW)                          //todo 5: make it an Assert
           then raise Exception.Create('Invalid KernOffset!');

           sum:= sum + ( img[ImgOffset + u] * k.KernelW[KernOffset] );
           Inc(KernOffset);
         end;
       end;
      dst[PixelY * dst_w + PixelX]:= sum*scale;
     end;

  rw:= dst_w;
  rh:= dst_h;
end;

// _iqa_img_filter
// not implemented


{ Returns the filtered version of the specified pixel. If no kernel is given, the raw pixel value is returned.
  Params:
    img Source image
    w Image width
    ImgHeigth Image height
    x The x location of the pixel to filter
    y The y location of the pixel to filter
    k Optional. The convolution kernel to apply to the pixel.
    kscale The scale of the kernel (for normalization). 1 for normalized kernels. Required if 'k' is not null.

   returns: The filtered pixel value. }
function FilterPixel(img: RealImage; ImgWidth, ImgHeigth: integer; PixelX, PixelY: integer; k: TKernelAttrib; kscale: single): single;
var
   u,v: integer;
   uc,vc: integer;
   kx, ky: integer;
   kw_even, kh_even: integer;
   x_edge_left : integer;
   x_edge_right: integer;
   y_edge_top  : integer;
   y_edge_bottom: integer;
   edge: boolean;
   ImgOffset: integer;
   KernOffset: integer; // Kernel offset
   sum: Single;
begin
  if Length(k.KernelW)= 0
  then Exit(img[PixelY* ImgWidth + PixelX]);

  uc:= k.Width DIV 2;
  vc:= k.Height DIV 2;

  if Odd(k.width)          //  kw_even = (k->w&1)?0:1;
  then kw_even:= 0
  else kw_even:= 1;
  if Odd(k.Height)
  then kh_even:= 0
  else kh_even:= 1;

  x_edge_left  := uc;
  x_edge_right := ImgWidth-uc;
  y_edge_top   := vc;
  y_edge_bottom:= ImgHeigth-vc;
  edge:= (PixelX < x_edge_left) OR (Pixely < y_edge_top) OR (PixelX >= x_edge_right) OR (Pixely >= y_edge_bottom);

  sum:= 0;
  KernOffset:= 0;
  ky:= PixelY+ vc;
  kx:= PixelX+ uc;
  for v:= -vc to vc-kh_even do
   begin
    ImgOffset:= (ky + v)*ImgWidth + kx;
    for u := -uc to uc-kw_even DO
     begin
      Assert(KernOffset <= Length(k.KernelW), 'k_offset not < Length(k.kernel)!');

      if ImgOffset + u < 0                                        //todo 4: convert it to Assertion to make it faster
      then Exception.Create('Invalid ImgOffset!');

      if KernOffset >= Length(k.KernelW)                          //todo 4: convert it to Assertion to make it faster
      then raise Exception.Create('Invalid KernOffset!');

      if NOT edge
      then sum:= sum + (img[ImgOffset + u] * k.KernelW[KernOffset])
      else sum:= sum + (k.bnd_opt(img, ImgWidth, ImgHeigth, Pixelx+u, Pixely+v, k.bnd_const) * k.KernelW[KernOffset]);
      Inc(KernOffset);
     end;
   end;

 Result := sum * kscale;
end;

end.
