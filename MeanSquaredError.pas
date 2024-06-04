UNIT MeanSquaredError;

{=============================================================================================================
   Gabriel Moraru
   2024.05

   This is a port (but contains also major reworks) from C to Delphi.
   The original C code can be downloaded from http://tdistler.com/iqa
--------------------------------------------------------------------------------------------------------------
   Mean Squared Error

   Calculates the Mean Squared Error between 2 equal-sized 8-bit images.
   note The images must have the same width, height, and stride.

   Params:
       ReferenceImg Original  image
       CompareImage Distorted image

  Mean Squared Error
    is the average squared difference between a reference image and a distorted image.
    It is computed pixel-by-pixel by adding up the squared differences of all the pixels and dividing by the total pixel count.
    MSE(a,b) = 1/N * SUM((a-b)^2)

    For images A = [a1 .. aM] and B = [b1 .. bM], where M is the number of pixels:
    The squaring of the differences dampens small differences between the 2 pixels but penalizes large ones.

  More info:
    http://en.wikipedia.org/wiki/Mean_squared_error
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES SsimDef;

function mse(ReferenceImg, CompareImg: ByteImage; ImgWidth, ImgHeigth, stride: integer): Single;


IMPLEMENTATION


function mse(ReferenceImg, CompareImg: ByteImage; ImgWidth, ImgHeigth, stride: integer): Single;  // Returns: MSE
var
   error: Single;
   offset: integer;
   sum: Int64;
   ww: integer;
   hh: integer;
begin
  sum:= 0;
  Assert(Length(ReferenceImg) = Length(CompareImg), 'The images must have the same width, height, and stride!');
  for hh:= 0 to ImgHeigth-1 do
   begin
    offset:= hh*stride; 
    for ww:= 0 to ImgWidth-1 DO
      begin
       error:= ReferenceImg[offset] - CompareImg[offset];
       sum:= sum + round(error*error);
       inc(offset);
      end;
   end;

 result:= sum / (ImgWidth*ImgHeigth);
end;

end.
