{-
the following (currently 5) sparse formats will live here


DirectSparse 1dim



one subtlety and a seemingly subtle point will be
that contiguous / inner contiguous sparse arrays
in  2dim  (and  1dim) will have an ``inner dimension" shift int.
This is so that slices can  be zero copy on *BOTH* the array of values,
and the Format indexing array machinery.

Note that in the 2dim case, it still wont quite be zero copy, because the
offsets into the inner dimension lookup table (not quite the right word)
will have to change when a general slice is used rather than a slice
that acts only on the outermost dimension.
-}



-- {-# LANGUAGE PolyKinds   #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE StandaloneDeriving#-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE FlexibleContexts #-}

#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 707
 {-# LANGUAGE AutoDeriveTypeable #-}
#endif
module Numerical.Array.Layout.Sparse(
  SparseLayout(..)
  ,DirectSparse
  ,CSR
  ,CSC
  ,CompressedSparseRow
  ,CompressedSparseColumn --  FIX ME, re add column support later
  ,Format(FormatDirectSparseContiguous
      ,FormatContiguousCompressedSparseRow
      ,FormatInnerContiguousCompressedSparseRow
      ,FormatContiguousCompressedSparseColumn
      ,FormatInnerContiguousCompressedSparseColumn)
  ,ContiguousCompressedSparseMatrix(..)
  ,InnerContiguousCompressedSparseMatrix(..)
  ) where

import Data.Data
import Data.Bits (unsafeShiftR)
import Control.Applicative
import Numerical.Array.Layout.Base
import Numerical.Array.Shape
import Numerical.Array.Address
import qualified  Data.Vector.Generic as V

data CompressedSparseRow
  deriving Typeable
type CSR = CompressedSparseRow

data CompressedSparseColumn
    deriving Typeable

type CSC = CompressedSparseColumn

data DirectSparse
    deriving Typeable



data instance Format DirectSparse  Contiguous (S Z) rep =
    FormatDirectSparseContiguous {
      _logicalShapeDirectSparse:: {-# UNPACK#-} !Int
      ,_logicalBaseIndexShiftDirectSparse::{-# UNPACK#-} !Int
      ,_indexTableDirectSparse :: ! ((BufferPure rep) Int )  }
    --deriving (Show,Eq,Data)



{-
for some listings of the design space of Sparse matrices
as found in other tools,
see < https://software.intel.com/sites/products/documentation/doclib/mkl_sa/11/mklman/GUID-9FCEB1C4-670D-4738-81D2-F378013412B0.htm >

<  http://netlib.org/linalg/html_templates/node90.html > is also pretty readable

theres a subtle detail about the invariants of contiguous vs inner inner contiguous
for CSR and CSC
when I do an inner contiguous / contiguous slice / projection,
what "address shifts" do i need to track to make sure the slices
are zero copy as much as possible

just slicing on the outer dimension doesn't need any row shifts,
but a generalized (a,b) ... (a+x,b+y) selection when a,b!=0 does need a inner
dim shift,

NOTE that translating the inner dimension table's addresses to the corresponding
value buffer's address can require a shift!
This will happen when doing a MajorAxis (outer dimension) slice
the picks out a Suffix of the CSR matrix's rows


note that there are 2 formulations of CSR (/ CSC) formats

a) 3 array: value, column index,  and  row start vectors

b) 4 array: value, column index, rowstart, and row end vectors

lets use choice a) for contiguous vectors, and choice b) for
inner contiguous vectors.

In both cases we need to enrich the type with a "buffer shift"
to handle correctly doing lookups on submatrices picked out
by either a major axis slice

-}


--deriving instance (Show (Shape (S (S Z)) Int), Show (BufferPure rep Int) )
    -- => Show (Format CompressedSparseRow Contiguous (S (S Z)) rep)

--deriving instance  (Eq (Shape (S (S Z)) Int), Eq (BufferPure rep Int) )
    -- => Eq (Format CompressedSparseRow Contiguous (S (S Z)) rep)

--deriving instance (Data (Shape (S (S Z)) Int), Data (BufferPure rep Int) )
  --- => Data (Format CompressedSparseRow Contiguous (S (S Z)) rep)

--deriving instance  (Typeable (Shape (S (S Z)) Int ), Typeable (BufferPure rep Int) )
 -- => Typeable (Format CompressedSparseRow Contiguous (S (S Z)) rep)
    --deriving (Eq,Data,Typeable)


{-
NOTE!!!!!
logicalValueBufferAddressShiftContiguousCSR (and friends)
are so that major axis slices can still use the same buffer,
(needed for both Contiguous and InnerContiguous cases).
So When looking up the Address for a value based upon its
Inner dimension, we need to *SUBTRACT* that shift
to get the correct offset index into the current SLICE.

Phrased differently, This address shift is the *Discrepancy/Difference*
between the size of the elided prefix of the Vector and the starting
position of the manifest entries.

(Q: does this ever ever matter, or can i punt that to vector, and only
need this )


This is kinda a good argument for not punting the Slicing on the raw buffers to
Vector, because it generally makes this a bit more subtle to think about
and someone IS going to implement something wrong this way!


Another subtle and potentially confusing point is distinguishing between
Affine shifts in the Index Space vs the Address space.

Only the outer dimension lookup table shift is needed in the Contiguous
2dim case, but the 2dim InnerContiguous case is a bit more confusing
because of the potential for a slice along the inner dimension

Rank 1 sparse  (like Direct sparse) is only Contiguous,
and either a) doesn't need a shift, or b) only needs an index shift
commensurate matching the leading implicit index of a Major Axis Slice


theres a BIG corner case in most standard CSR / CSC formats which is
underspecified in most docs about CSC and CSR formats.
Consider Without loss of generality, CSR format
  1) how are empty rows modeled/signaled?
  2) if the last row is empty, how is that signaled?

2) The last row is signaled to be be empty by having
  the last entry of _outerDim2InnerDim buffer be set to >=
  length of _innerDimIndex buffer (ie >= 1 + largest index of _innerDimIndex)
1)

note that the outer index table has 1+#rows length, with the last one being the
length of the array

-}

data ContiguousCompressedSparseMatrix rep =
    FormatContiguousCompressedSparseInternal {
      _outerDimContiguousSparseFormat ::  {-# UNPACK #-} !Int
      ,_innerDimContiguousSparseFormat ::  {-# UNPACK #-} !Int
      ,_innerDimIndexContiguousSparseFormat :: !(BufferPure rep Int)
      ,_outerDim2InnerDimContiguousSparseFormat:: ! (BufferPure rep Int )
  }
{-
  outerDim innerDim  innerTable  outer2InnerStart
-}



{-
for Row major Compressed Sparse (CSR)
the X dim (columns) are the inner dimension, and Y dim (rows) are the outer dim
-}



data  InnerContiguousCompressedSparseMatrix rep =
   FormatInnerContiguousCompressedSparseInternal {
      _outerDimInnerContiguousSparseFormat ::    {-# UNPACK #-} !Int
      ,_innerDimInnerContiguousSparseFormat ::  {-# UNPACK #-} !Int
      ,_innerDimIndexShiftInnerContiguousSparseFormat:: {-# UNPACK #-} !Int

      ,_innerDimIndexInnerContiguousSparseFormat :: !(BufferPure rep Int)
      ,_outerDim2InnerDimStartInnerContiguousSparseFormat:: ! (BufferPure rep Int )
      ,_outerDim2InnerDimEndInnerContiguousSparseFormat:: ! (BufferPure rep Int )
         }
newtype instance Format CompressedSparseRow Contiguous (S (S Z)) rep =
    FormatContiguousCompressedSparseRow {
      _getFormatContiguousCSR :: (ContiguousCompressedSparseMatrix rep) }

newtype instance Format CompressedSparseColumn Contiguous (S (S Z)) rep =
    FormatContiguousCompressedSparseColumn {
      _getFormatContiguousCSC :: (ContiguousCompressedSparseMatrix rep) }


newtype instance Format CompressedSparseRow InnerContiguous (S (S Z)) rep =
    FormatInnerContiguousCompressedSparseRow {
      _getFormatInnerContiguousCSR :: (InnerContiguousCompressedSparseMatrix rep )
  }


newtype instance Format CompressedSparseColumn InnerContiguous (S (S Z)) rep =
    FormatInnerContiguousCompressedSparseColumn {
      _getFormatInnerContiguousCSC :: (InnerContiguousCompressedSparseMatrix rep )
  }

      --deriving (Show,Eq,Data)

{-
  FormatInnerContiguous rowsize columnsize

-}


--newtype instance Format CompressedSparseColumn Contiguous (S (S Z)) rep =
--    FormatContiguousCompressedSparseColumn {
--      _getFormatContiguousCSC ::  (ContiguousCompressedSparseMatrix rep)
--  }
    --deriving (Show,Eq,Data)

--newtype  instance Format CompressedSparseColumn InnerContiguous (S (S Z)) rep =
--    FormatInnerContiguousCompressedSparseColumn {
--     _getFormatInnerContiguousCSC :: (InnerContiguousCompressedSparseMatrix rep)
--  }
--    --deriving (Show,Eq,Data)



class Layout form rank  => SparseLayout form  (rank :: Nat)  | form -> rank where

    type SparseLayoutAddress form :: *

    minSparseAddress ::  (address ~ SparseLayoutAddress form)=> form -> Maybe address

    maxSparseAddress ::  (address ~ SparseLayoutAddress form)=> form -> Maybe address

    basicToSparseAddress :: (address ~ SparseLayoutAddress form)=>
        form  -> Shape rank Int -> Maybe  address


    basicToSparseIndex ::(address ~ SparseLayoutAddress form)=>
        form -> address -> Shape rank Int


    basicNextAddress :: (address ~ SparseLayoutAddress form)=>
        form  -> address -> Maybe  address

    {-# INLINE basicNextIndex #-}
    basicNextIndex :: form  -> Shape rank Int -> Maybe  (Shape rank Int)
    basicNextIndex =
        \ form shp ->
          basicToSparseAddress form shp >>=
            (\x ->  fmap (basicToSparseIndex form)  $  basicNextAddress form x)

    {-# MINIMAL basicToSparseAddress, basicToSparseIndex, basicNextAddress
      ,maxSparseAddress, minSparseAddress #-}





--CSR and CSC go here, and their version of lookups and next address and next index






--  Offset binary search --- cribbed with permission from
-- edward kmett's structured lib



-- Assuming @l <= h@. Returns @h@ if the predicate is never @True@ over @[l..h)@
--searchUp :: (Int -> Bool) -> Int -> Int -> Int
--searchUp p = go where
--  go l h
--    | l == h    = l
--    | p m       = go l m
--    | otherwise = go (m+1) h
--    where hml = h - l
--          m = l + unsafeShiftR hml 1 + unsafeShiftR hml 6
--{-# INLINE searchUp #-}

---- Assuming @l <= h@. Returns @l@ if the predicate is never @True@ over @(l..h]@
--searchDown :: (Int -> Bool) -> Int -> Int -> Int
--searchDown p = go where
--  go l h
--    | l == h    = l
--    | p (m+1)       = go (m+1) h
--    | otherwise = go l m
--    where hml = h - l
--          m = l + unsafeShiftR hml 1 + unsafeShiftR hml 6
--{-# INLINE searchDown #-}


-- Assuming @l <= h@. Returns @h@ if the predicate is never @True@ over @[l..h)@
linearSearchUp :: (Int -> Bool)-> Int -> Int -> Int
linearSearchUp p = go where
  go l h
    | l ==h = l
    | p l = l
    | otherwise = go (l+1) h
{-#INLINE linearSearchUp #-}

-- Assuming @l <= h@. Returns @l@ if the predicate is never @True@ over @(l..h]@
linearSearchDown :: (Int -> Bool)-> Int -> Int -> Int
linearSearchDown p = go where
  go l h
    | l ==h = l
    | p h = h
    | otherwise = go l (h-1)
{-#INLINE linearSearchDown #-}




--
-- now assumed each key is unique and ordered
--
-- Assuming @l <= h@. Returns @h@ if the predicate is never @True@ over @[l..h)@

-- should at some point try out a ternary search scheme to have even better
-- cache behavior (and benchmark of course)

searchOrd :: (Int -> Ordering) -> Int -> Int -> Int
searchOrd  p = go where
  go l h
    | l == h    = l
    | otherwise = case p m of
                  LT -> go (m+1) h
                  ---  entry is less than target, go up!
                  EQ -> m
                  -- we're there! Finish early
                  GT -> go l m
                  -- entry is greater than target, go down!
    where hml = h - l
          m = l + unsafeShiftR hml 1 + unsafeShiftR hml 6
{-# INLINE searchOrd #-}

lookupExact :: (Ord k, V.Vector vec k) => vec k -> k -> Maybe Int
lookupExact ks key
  | j <- searchOrd (\i -> compare (ks V.! i)  key) 0 (V.length ks - 1)
  , ks V.! j == key = Just $! j
  | otherwise = Nothing
{-# INLINE lookupExact #-}

lookupExactRange :: (Ord k, V.Vector vec k) => vec k -> k -> Int -> Int -> Maybe Int
lookupExactRange  ks key lo hi
  | j <- searchOrd (\i -> compare (ks V.! i)  key) lo hi
  , ks V.! j == key = Just $! j
  | otherwise = Nothing
{-# INLINE lookupExactRange  #-}

--lookupLUB ::  (Ord k, V.Vector vec k) => vec k -> k -> Maybe Int
--lookupLUB  ks key
--  | j <- search  (\i -> compare (ks V.! i)  key) 0 (V.length ks - 1)
--  , ks V.! j <= key = Just $! j
--  | otherwise = Nothing
--{-# INLINE lookupLUB  #-}

type instance  Transposed (Format DirectSparse Contiguous (S Z) rep )=
   (Format DirectSparse Contiguous (S Z) rep )

instance Layout   (Format DirectSparse Contiguous (S Z) rep ) (S Z) where
  transposedLayout  = id
  {-# INLINE transposedLayout #-}
  basicFormShape = \ form -> _logicalShapeDirectSparse form  :* Nil
  {-# INLINE basicFormShape #-}
  basicCompareIndex = \ _ (a:* Nil) (b :* Nil) ->compare a b
  {-# INLINE basicCompareIndex#-}

instance V.Vector (BufferPure rep) Int
   => SparseLayout  (Format DirectSparse Contiguous (S Z) rep ) (S Z) where
      type SparseLayoutAddress (Format DirectSparse Contiguous (S Z) rep) =  Address

      minSparseAddress =
        \ (FormatDirectSparseContiguous _ _   lookupTable)->
            if  V.length lookupTable >0 then  Just $! Address 0 else Nothing

      maxSparseAddress =
        \ (FormatDirectSparseContiguous _ _   lookupTable)->
          if (V.length lookupTable >0 )
             then Just $! Address (V.length lookupTable - 1 )
             else Nothing

-- TODO, double check that im doing shift correctly
      {-# INLINE basicToSparseAddress #-}
      basicToSparseAddress =
          \ (FormatDirectSparseContiguous shape  indexshift lookupTable) (ix:*_)->
             if  not (ix < shape && ix > 0 ) then  Nothing
              else  fmap Address  $! lookupExact lookupTable (ix + indexshift)

      {-# INLINE basicToSparseIndex #-}
      basicToSparseIndex =
        \ (FormatDirectSparseContiguous _ shift lut) (Address addr) ->
            ((lut V.! addr ) - shift) :* Nil

      {-# INLINE basicNextAddress #-}
      basicNextAddress =
        \ (FormatDirectSparseContiguous _ _ lut) (Address addr) ->
          if  addr >= (V.length lut) then Nothing else Just  (Address (addr+1))


------------
------------

type instance Transposed (Format CompressedSparseRow Contiguous (S (S Z)) rep )=
    (Format CompressedSparseColumn Contiguous (S (S Z)) rep )

type instance Transposed (Format CompressedSparseColumn Contiguous (S (S Z)) rep )=
    (Format CompressedSparseRow Contiguous (S (S Z)) rep )


instance Layout (Format CompressedSparseRow Contiguous (S (S Z)) rep ) (S (S Z)) where
  transposedLayout  = \(FormatContiguousCompressedSparseRow repFormat) ->
    (FormatContiguousCompressedSparseColumn  repFormat)
  {-# INLINE transposedLayout #-}
  basicFormShape = \ form ->  (_innerDimContiguousSparseFormat $ _getFormatContiguousCSR  form ) :*
         ( _outerDimContiguousSparseFormat $ _getFormatContiguousCSR form ):* Nil
          --   x_ix :* y_ix
  {-# INLINE basicFormShape #-}


  basicCompareIndex = \ _ as  bs ->shapeCompareRightToLeft as bs
  {-# INLINE basicCompareIndex#-}

instance  (V.Vector (BufferPure rep) Int )
  => SparseLayout (Format CompressedSparseRow Contiguous (S (S Z)) rep ) (S (S Z)) where

      type SparseLayoutAddress (Format CompressedSparseRow Contiguous (S (S Z)) rep ) = SparseAddress

      {-# INLINE minSparseAddress #-}
      minSparseAddress =
        \(FormatContiguousCompressedSparseRow
            (FormatContiguousCompressedSparseInternal  y_row_range x_col_range    columnIndex rowStartIndex)) ->
                if ( y_row_range < 1  || x_col_range < 1|| (V.length columnIndex  < 1) )
                  then Nothing
                  else
                  -- the value buffer has the invariant the the end points
                  -- of the buffer MUST be valid  in bounds values if length buffer > 0
                --SparseAddress $! 0 $! 0

                -- hoisted where into if branch as let so lets could be strict
                    let
                      !addrShift = columnIndex V.! 0

                      -- for now assuming candidateRow is ALWAYS valid
                      --- haven't proven this, FIXME
                      !candidateRow= linearSearchUp nonZeroRow 0 (y_row_range-1 )


                      {- FIXME, to get the right complexity
                      to linear search on first log #rows + 1 slots, then fall
                      back to binary search
                      punting for now because this probably wont matter than often

                      the solution will be to replace linearSearchUp
                      with a hybridSearchUp
                       -}
                      nonZeroRow =
                          \ !row_ix ->
                               -- the first row to satisfy this property
                              (rowStartIndex V.! (row_ix+1) >  rowStartIndex V.! row_ix)
                              -- if the start index is >0, already past the min address row!
                                ||  (rowStartIndex V.! row_ix) - addrShift > 0

                              --else  maxIxP1 >  rowStartIndex V.! row_ix
                    in Just $! SparseAddress  (candidateRow) $! 0

      {-# INLINE maxSparseAddress#-}
      maxSparseAddress  =
        \(FormatContiguousCompressedSparseRow
            (FormatContiguousCompressedSparseInternal  y_row_range x_col_range    columnIndex rowStartIndex)) ->
                if ( y_row_range < 1  || x_col_range < 1|| (V.length columnIndex  < 1) )
                  then Nothing
                  else
                  -- the value buffer has the invariant the the end points
                  -- of the buffer MUST be valid  in bounds values if length buffer > 0
                --SparseAddress $! 0 $! 0

                -- hoisted where into if branch as let so lets could be strict
                    let
                      !addrShift = columnIndex V.! 0
                      !maxIxP1 = V.length columnIndex

                      -- for now assuming candidateRow is ALWAYS valid
                      --- haven't proven this, FIXME
                      !candidateRow= linearSearchDown nonZeroRow 0 (y_row_range-1 )


                      {- FIXME, to get the right complexity
                      to linear search on last log #rows + 1 slots, then fall
                      back to binary search
                      punting for now because this probably wont matter than often

                      the solution will be to replace linearSearchDown
                      with a hybridSearchDown
                       -}
                      nonZeroRow =
                          \ !row_ix ->
                       -- the first row to satisfy this property (going down from last row)
                              (rowStartIndex V.! (row_ix+1) >  rowStartIndex V.! row_ix)
                      -- if the start index is >= maxIxP1, havent gone down to max addres yet
                      -- if < maxIxp1, we're at or below the max address
                                ||  (rowStartIndex V.! row_ix) - addrShift < maxIxP1

                              --else  maxIxP1 >  rowStartIndex V.! row_ix
                    in
                        Just $!
                         SparseAddress  candidateRow $! (V.length columnIndex - 1 )

       -- \ (FormatContiguousCompressedSparseRow (FormatContiguousCompressedSparseInternal _ y_range
       --          columnIndex _)) ->
       --       SparseAddress (y_range - 1) (V.length columnIndex - 1 )


      {-# INLINE basicToSparseIndex #-}
      basicToSparseIndex =
        \ (FormatContiguousCompressedSparseRow
            (FormatContiguousCompressedSparseInternal  _ _ columnIndex _))
            (SparseAddress outer inner) ->
              (columnIndex V.! inner ) :* outer :*  Nil
          -- outer is the row (y index) and inner is the lookup position for the x index


{-
theres 3 cases for contiguous next address:
in the middle of a run on a fixed outer dimension,
need to bump the outer dimension, or we're at the end of the entire array

we make the VERY strong assumption that no illegal addresses are ever made!

note that for very very small sparse matrices, the branching will have some
overhead, but in general branch prediction should work out ok.
-}
      {-# INLINE basicNextAddress #-}
      basicNextAddress =
         \ (FormatContiguousCompressedSparseRow
            (FormatContiguousCompressedSparseInternal  _ _
              columnIndex rowStartIndex))
            (SparseAddress outer inner) ->
              if  inner < (V.length columnIndex -1)
               -- can advance further
                 -- && ( outer == (y_row_range-1)
                  --- either last row
                  || ((inner +1) < (rowStartIndex V.! (outer + 1)  - (rowStartIndex V.! 0 )))
                     -- or our address is before the next row starts
                     -- 3 vector CSR has a +1 slot at the end of the rowStartIndex

                then
                  Just (SparseAddress outer (inner+1))
                else
                  if inner == (V.length columnIndex -1)
                    then Nothing
                    else Just (SparseAddress (outer + 1) (inner + 1 ) )

        --  error "finish me damn it"
      {-# INLINE basicToSparseAddress #-}
      basicToSparseAddress =
        \ (FormatContiguousCompressedSparseRow
            (FormatContiguousCompressedSparseInternal  y_row_range x_col_range
              columnIndex rowStartIndex))
          (ix_x:*ix_y :* _ ) ->
            if  not (ix_x >= x_col_range ||  ix_y >=y_row_range )
              then
              -- slightly different logic when ix_y < range_y-1 vs == range_y-1
              -- because contiguous, don't need the index space shift though!
                let
                  shift = (rowStartIndex V.! 0)
                  checkIndex i =
                      if  (columnIndex V.!i) == ix_x
                        then Just i
                        else Nothing
                in
                 (SparseAddress ix_y  <$>) $!
                    checkIndex =<<
                 --- FIXME  : need to check
                      lookupExactRange columnIndex ix_x
                          ((rowStartIndex V.! ix_y) - shift)
                          ((rowStartIndex V.! (ix_y+1) ) - shift)

              else   (Nothing :: Maybe SparseAddress )



-------
-------



--type instance Transposed (Format CompressedSparseRow InnerContiguous (S (S Z)) rep )=
--    (Format CompressedSparseColumn InnerContiguous (S (S Z)) rep )

--type instance Transposed (Format CompressedSparseColumn InnerContiguous (S (S Z)) rep )=
--    (Format CompressedSparseRow InnerContiguous (S (S Z)) rep )


--instance Layout (Format CompressedSparseRow InnerContiguous (S (S Z)) rep ) (S (S Z)) where
--  transposedLayout  = \(FormatInnerContiguousCompressedSparseRow a b c d e f) ->
--    (FormatInnerContiguousCompressedSparseColumn a b c d e f)
--  {-# INLINE transposedLayout #-}
--  basicFormShape = \ form -> logicalRowShapeInnerContiguousCSR form  :*
--         logicalColumnShapeInnerContiguousCSR form :* Nil
--  {-# INLINE basicFormShape #-}
--  basicCompareIndex = \ _ as  bs ->shapeCompareRightToLeft as bs
--  {-# INLINE basicCompareIndex#-}



--instance  (V.Vector (BufferPure rep) Int )
--  => SparseLayout (Format CompressedSparseRow InnerContiguous (S (S Z)) rep ) (S (S Z)) where

--      type SparseLayoutAddress (Format CompressedSparseRow InnerContiguous (S (S Z)) rep ) = SparseAddress

--      {-# INLINE minSparseAddress #-}
--      minSparseAddress = \_ -> SparseAddress 0 0

--      {-# INLINE maxSparseAddress#-}
--      maxSparseAddress  =
--       \ (FormatInnerContiguousCompressedSparseInternal _ outer_dim_range _
--          innerDimIndex _) ->
--              SparseAddress (outer_dim_range - 1) (V.length innerDimIndex - 1 )


--      {-#INLINE basicToSparseIndex #-}
--      basicToSparseIndex =
--       \ (FormatInnerContiguousCompressedSparseInternal _ _  _ innerDimIndex _)
--          (SparseAddress outer inner) -> (innerDimIndex V.! inner ) :* outer :*  Nil
--          -- outer is the row (y index) and inner is the lookup position for the x index



--theres 3 cases for contiguous next address:
--in the middle of a run on a fixed outer dimension,
--need to bump the outer dimension, or we're at the end of the entire array

--we make the VERY strong assumption that no illegal addresses are ever made!

--note that for very very small sparse matrices, the branching will have some
--overhead, but in general branch prediction should work out ok.

--      {-# INLINE basicNextAddress #-}
--      basicNextAddress =
--         \ (FormatInnerContiguousCompressedSparseRow
--                (FormatInnerContiguousCompressedSparseInternal _ _ _
--                                                         columnIndex rowstartIndex))
--            (SparseAddress outer inner) ->
--              if not  (inner == (V.length columnIndex -1)
--                                          {- && outer == (y_range-1) -}
--                     || (inner +1) == (rowstartIndex V.! (outer + 1)))
--                then
--                  Just (SparseAddress outer (inner+1))
--                else
--                  if inner == (V.length columnIndex -1)
--                    then Nothing
--                    else Just (SparseAddress (outer + 1) (inner + 1 ) )

--        --  error "finish me damn it"
--      {-# INLINE basicToSparseAddress #-}
--      basicToSparseAddress =
--        \ (FormatInnerContiguousCompressedSparseRow
--            (FormatInnerContiguousCompressedSparseInternal x_range y_range addrShift
--                      columnIndex rowstartIndex))
--          (ix_x:*ix_y :* _ ) ->
--            if  not (ix_x >= x_range ||  ix_y >=y_range )
--              then
--              -- slightly different logic when ix_y < range_y-1 vs == range_y-1
--              -- because contiguous, don't need the index space shift though!
--                       SparseAddress ix_y   <$>
--                          lookupExactRange columnIndex ix_x ((rowstartIndex V.! ix_y) - addrShift)
--                            (if  ix_y < (y_range-1)
--                              -- addr shift is for correcting from a major axis slice
--                              then  (rowstartIndex V.! (ix_y+1) ) - addrShift
--                              else V.length columnIndex  - 1 )
--              else   (Nothing :: Maybe SparseAddress )