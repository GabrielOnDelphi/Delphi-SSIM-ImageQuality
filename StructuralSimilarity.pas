UNIT StructuralSimilarity;

{-------------------------------------------------------------------------------------------------------------
  Calculates the structural similarity between 2 images.
  MAIN FILE
  2019-08-16
--------------------------------------------------------------------------------------------------------------

  Note: The images must be equal as size and gray scale.
  See https://ece.uwaterloo.ca/~z70wang/publications/ssim.html

  ALGO:
    SSIM(x,y) = (2*ux*uy + C1)*(2sxy + C2) / (ux^2 + uy^2 + C1)*(sx^2 + sy^2 + C2) where:
     ux = SUM(w*x)
     sx = (SUM(w*(x-ux)^2)^0.5
     sxy = SUM(w*(x-ux)*(y-uy))
  Returns mean SSIM. MSSIM(X,Y) = 1/M * SUM(SSIM(x,y))

  SSIM
   Structural SIMilarity is based on the idea that the human visual system is highly adapted to process
   structural information, and the algorithm attepts to measure the change in this information between and
   reference and distorted image.

   Based on numberous tests, SSIM does a much better job at quantifying subjective image quality than MSE or PSNR.
  
   At a high level, SSIM attempts to measure the change in luminance, contrast, and structure in an image.
   Luminance is modeled as average pixel intensity,
    constrast by the variance between the reference and distorted image, and
    structure by the cross-correlation between the 2 images.

   The resulting values are combined (using exponents referred to as alpha, beta, and gamma) and
   averaged to generate a final SSIM index value.
  
   The original paper defined 2 methods for calculating each local SSIM value:
     an 8x8 linear
     or 11x11 circular Gaussian sliding window.

   This library uses the Gaussian window that the paper suggests to give the best results.
   However, the window type, stabilization constants, and exponents can all be set adjusted by the application.
  
   Here's an interesting article by the authors discussing the limitations of MSE and PSNR as compared to SSIM:
   https://ece.uwaterloo.ca/~z70wang/publications/SPM09.pdf

-------------------------------------------------------------------------------------------------------------}

//todo 3: rename 'ref' to 'RefBitmap'
//bug: there is a bug that makes the first computation to return a very low value. the subsequent computations seem ok. probably some bad initialization

INTERFACE
USES
   System.SysUtils, Vcl.Graphics, SsimDef;

// Main functions
function SsimCompare(refBMP, cmpBMP: TBitmap; WndType: TKernelWndType): Single;                                                                                   overload;
function SsimCompare(refBMP, cmp: ByteImage; ImgWidth, ImgHeigth, stride: Integer; KernelWndType: TKernelWndType; args: TSsimArgs): Single; overload;

IMPLEMENTATION

USES
   Math, Decimate, Convolve;



{---------------------------------------------------------------------------
   UTIL FUNCTIONS FOR _ssim
---------------------------------------------------------------------------}
function computeLuminance(mu1, mu2: single; C1: single; alpha: single): single;
VAR
   Rez: single;
begin
  // For MS-SSIM
  if (C1 = 0) and (mu1 = 0) and (mu2 = 0)
  then exit(1);

  Rez := (2 * mu1 * mu2 + C1) / (mu1 * mu1 + mu2 * mu2 + C1);
  if alpha = 1 then Exit(rez);

  if Rez < 0
  then Result := -Power(Abs(Rez), alpha)
  else Result :=  Power(Abs(Rez), alpha);
end;


function computeContrast(sigma_comb_12, sigma1_sqd, sigma2_sqd: single; C2: single; beta: single): single;
var
  Rez: single;
begin
  // For MS-SSIM
  if (C2 = 0) AND (sigma1_sqd + sigma2_sqd = 0)
  then EXIT(1);

  Rez := (2 * sigma_comb_12 + C2) / (sigma1_sqd + sigma2_sqd + C2);
  if beta = 1 then Exit(rez);

  if Rez < 0
  then Result:= -Power(Abs(Rez), beta)
  else Result:=  Power(Abs(Rez), beta);
end;


function computeStructure(sigma_12, sigma_comb_12, sigma1, sigma2: single; C3: single; gamma: single): single;
var
  Rez: single;
begin
  // For MS-SSIM
  if (C3 = 0) and (sigma_comb_12 = 0) then
    begin
      if (sigma1 = 0) and (sigma2 = 0)
      then exit(1)
      else
        if (sigma1 = 0) or (sigma2 = 0)
        then EXIT(0);
    end;

  Rez := (sigma_12 + C3) / (sigma_comb_12 + C3);
  if gamma = 1 then Exit(rez);

  if Rez < 0
  then Result := -Power(Abs(Rez), gamma)
  else Result :=  Power(Abs(Rez), gamma);
end;




{---------------------------------------------------------------------------
 Calculates the SSIM value on a pre-processed image.
 The input images must have stride=width. This method does not scale.
 Note: Image buffers are modified.

 Map-reduce is used for doing the final SSIM calculation.
 The map function is called for every pixel, and the reduce is called at the end.
 The context is caller-defined and *not* modified by this method.

 Parameters:
    ref : Original reference image
    cmp : Distorted image
    ImgWidth   : Width of the images
    ImgHeigth   : Height of the images
    k   : The kernel used as the window function
    mr  : Optional map-reduce functions to use to calculate SSIM.
          Required if 'args' is not null. Ignored if 'args' is null.
    args: Optional SSIM arguments for fine control of the algorithm. 0 for defaults.
          Defaults are a=b=g=1.0, L=255, K1=0.01, K2=0.03

 Returns: The mean SSIM over the entire image (MSSIM) }


function _ssim(ref, cmp: RealImage; ImgWidth, ImgHeigth: integer; k: TKernelAttrib; args: TSsimArgs): single;
VAR
  C1, C2, C3     : Single;
  x, y           : integer;
  dummy, offset  : integer;
  ref_mu         : RealImage;
  cmp_mu         : RealImage;
  ref_sigma_sqd  : RealImage;
  cmp_sigma_sqd  : RealImage;
  sigma_both     : RealImage;
  ssim_sum       : single;
  numerator      : single;
  denominator    : single;
  luminance_comp, contrast_comp, structure_comp : single;
  sigma_root     : single;
begin
  C1 := (args.K1 * args.L) * (args.K1 * args.L);
  C2 := (args.K2 * args.L) * (args.K2 * args.L);
  C3 := C2 / 2;

  // Calculate mean
  SetLength(ref_mu,        ImgWidth * ImgHeigth);
  SetLength(cmp_mu,        ImgWidth * ImgHeigth);
  SetLength(ref_sigma_sqd, ImgWidth * ImgHeigth);
  SetLength(cmp_sigma_sqd, ImgWidth * ImgHeigth);
  SetLength(sigma_both,    ImgWidth * ImgHeigth);

  ConvolveImage(ref, ImgWidth, ImgHeigth, k, ref_mu, dummy, dummy);
  ConvolveImage(cmp, ImgWidth, ImgHeigth, k, cmp_mu, dummy, dummy);
  for y := 0 to ImgHeigth-1 do
   begin
    offset := y * ImgWidth;
    for x := 0 to ImgWidth-1 do
    begin
      ref_sigma_sqd[offset] := ref[offset] * ref[offset];
      cmp_sigma_sqd[offset] := cmp[offset] * cmp[offset];
      sigma_both[offset]    := ref[offset] * cmp[offset];
      Inc(offset);
    end;
   end;

  // Calculate sigma
  ConvolveImage(ref_sigma_sqd, ImgWidth, ImgHeigth, k, NIL, dummy, dummy);
  ConvolveImage(cmp_sigma_sqd, ImgWidth, ImgHeigth, k, NIL, dummy, dummy);
  ConvolveImage(sigma_both,    ImgWidth, ImgHeigth, k, NIL, ImgWidth, ImgHeigth); // was  convolve(sigma_both, w, h, k, 0, &w, &h);

  (* Update the width and height *)
  // The convolution results are smaller by the kernel width and height
  for y := 0 to ImgHeigth-1 do
    begin
      offset := y * ImgWidth;
      for x := 0 to ImgWidth-1 do
      begin
        ref_sigma_sqd[offset] := ref_sigma_sqd[offset] - (ref_mu[offset] * ref_mu[offset]);
        cmp_sigma_sqd[offset] := cmp_sigma_sqd[offset] - (cmp_mu[offset] * cmp_mu[offset]);
        sigma_both[offset]    := sigma_both[offset]    - (ref_mu[offset] * cmp_mu[offset]);
        Inc(offset);
      end;
    end;

  ssim_sum := 0;
  for y := 0 to ImgHeigth-1 do
   begin
    offset := y * ImgWidth;
    for x := 0 to ImgWidth-1 DO
     begin
      if NOT args.CustomParams then
        begin
          // The default case
          numerator   := (2.0 * ref_mu[offset] * cmp_mu[offset] + C1) * (2.0 * sigma_both[offset] + C2);
          denominator := (ref_mu[offset] * ref_mu[offset]  +  cmp_mu[offset] * cmp_mu[offset] + C1) * (ref_sigma_sqd[offset]  +  cmp_sigma_sqd[offset] + C2);
          ssim_sum    := ssim_sum + (numerator / denominator);
        end
      else
        begin
          // User defined alpha, beta, or gamma

          // Prevent passing negative numbers to sqrt
          if ref_sigma_sqd[offset] < 0
          then ref_sigma_sqd[offset] := 0;
          if cmp_sigma_sqd[offset] < 0
          then cmp_sigma_sqd[offset] := 0;

          sigma_root := sqrt(ref_sigma_sqd[offset] * cmp_sigma_sqd[offset]);

          // Hold intermediate SSIM values for map-reduce operation
          luminance_comp := computeluminance(ref_mu[offset], cmp_mu[offset], C1, args.alpha);
          contrast_comp  := computecontrast (sigma_root, ref_sigma_sqd[offset], cmp_sigma_sqd[offset], C2, args.beta);
          structure_comp := computestructure(sigma_both[offset], sigma_root, ref_sigma_sqd[offset], cmp_sigma_sqd[offset], C3, args.gamma);

          // Holds intermediate SSIM values for map-reduce operation.
          ssim_sum := ssim_sum + luminance_comp * contrast_comp * structure_comp;
        end;

      Inc(offset); 
     end;
  end;

  Result := ssim_sum / (ImgWidth * ImgHeigth); // mr->reduce(w, h, mr->context);
end;





{ Calculates the Structural SIMilarity between 2 equal-sized 8-bit images.
  Params:
     ref        Original reference image
     cmp        Distorted image
     ImgWidth   Width of the images
     ImgHeigth  Height of the images
     stride     The length (in bytes) of each horizontal line in the image.
                This may be different from the image width.
     gaussian 0 = 8x8 square window,
              1 = 11x11 circular-symmetric Gaussian weighting.
     args       Optional SSIM arguments for fine control of the algorithm. 0 for defaults.
     Defaults are: a=b=g=1, L=255, K1=0.01, K2=0.03

  return: The mean SSIM over the entire image (MSSIM), or INFINITY if error.
  note: The images must have the same width, height, and stride. }

function SsimCompare(refBMP, cmpBMP: TBitmap; WndType: TKernelWndType): Single;
CONST
   Components = 1;
VAR
   ref, cmp: ByteImage;
   Stride: integer;
   args: TSsimArgs;
begin
  { Convert pixels to gray and transfer them from a TBitmap to a unidimensional array (of size Width*Height) }
  ref:= TransferPixels(refBMP);
  cmp:= TransferPixels(cmpBMP);
  stride:= GetStride(refBMP);  //del: refBMP.Width * Components;

  args.Init;
  args.ScaleFactor := sfAuto;

  Result:= SsimCompare(ref, cmp, refBMP.Width, refBMP.Height, Stride, WndType, args);
end;


function SsimCompare(refBMP, cmp: ByteImage; ImgWidth, ImgHeigth, stride: Integer; KernelWndType: TKernelWndType; args: TSsimArgs): single;
VAR
   scale, offset: integer;
   x, y         : integer;
   src_offset   : Integer;
   ref_f, cmp_f : RealImage;
   low_pass     : TKernelAttrib;
   window       : TKernelAttrib;
   dummy, SqrScale : Integer;
begin
  // Initialization
  case args.ScaleFactor of
     sfNone: scale := 1;
     sfAuto: scale := max(1, roundEx(min(ImgWidth, ImgHeigth) / 256));
    else
      RAISE Exception.Create('Invalid scale factor!');
  end;

  //if args.CustomParams then mr.context := ssim_sum;
  window.normalized := TRUE;
  window.bnd_opt    := KBND_SYMMETRIC;
  SetKernelWindow(window, KernelWndType);

  // Convert image pixels to floats. We force stride = width.
  SetLength(ref_f, ImgWidth * ImgHeigth);
  SetLength(cmp_f, ImgWidth * ImgHeigth);

  for y := 0 to ImgHeigth-1 do
   begin
    src_offset := y * stride;
    offset := y * ImgWidth;
    for x := 0 to ImgWidth-1 DO
     begin
      ref_f[offset] := refBMP[src_offset];   // Range check error HERE
      cmp_f[offset] := cmp[src_offset];
      Inc(offset);
      Inc(src_offset);
     end;
   end;

  { Scale the images down IF required }
  if scale > 1 then
    begin
      // Generate simple low-pass filter
      SetLength(low_pass.KernelW, scale * scale);
      low_pass.width  := scale;
      low_pass.Height := scale;
      low_pass.normalized := FALSE;
      low_pass.bnd_opt := KBND_SYMMETRIC;

      SqrScale:= scale * scale;
      for offset := 0 to SqrScale-1
       DO low_pass.KernelW[offset] := 1 / SqrScale;

      // Resample both images. Takes too long without this
      DecimateImage(ref_f, ImgWidth, ImgHeigth, scale, low_pass, NIL, dummy, dummy);
      DecimateImage(cmp_f, ImgWidth, ImgHeigth, scale, low_pass, NIL, ImgWidth, ImgHeigth);
    end;

  result := _ssim(ref_f, cmp_f, ImgWidth, ImgHeigth, window, args);
end;





{function ssimReduce(w, h: integer; ctx: Single): Single;
begin
  Result := ctx / (w*h);
end;}


end.


