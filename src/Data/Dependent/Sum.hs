{-# LANGUAGE ExistentialQuantification, GADTs #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE CPP #-}
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Safe #-}
#endif
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 708
{-# LANGUAGE PolyKinds #-}
#endif
module Data.Dependent.Sum where

-- import Control.Applicative

#if MIN_VERSION_base(4,7,0)
import Data.Typeable (Typeable)
#else
import Data.Dependent.Sum.Typeable ({- instance Typeable ... -})
#endif

import Data.GADT.Show
import Data.GADT.Compare

import Data.Maybe (fromMaybe)
import Data.Kind


type family DSumC a :: Constraint
-- |A basic dependent sum type; the first component is a tag that specifies 
-- the type of the second;  for example, think of a GADT such as:
-- 
-- > data Tag a where
-- >    AString :: Tag String
-- >    AnInt   :: Tag Int
-- 
-- Then, we have the following valid expressions of type @Applicative f => DSum Tag f@:
--
-- > AString ==> "hello!"
-- > AnInt   ==> 42
-- 
-- And we can write functions that consume @DSum Tag f@ values by matching, 
-- such as:
-- 
-- > toString :: DSum Tag Identity -> String
-- > toString (AString :=> Identity str) = str
-- > toString (AnInt   :=> Identity int) = show int
-- 
-- By analogy to the (key => value) construction for dictionary entries in
-- many dynamic languages, we use (key :=> value) as the constructor for
-- dependent sums.  The :=> and ==> operators have very low precedence and
-- bind to the right, so if the @Tag@ GADT is extended with an additional
-- constructor @Rec :: Tag (DSum Tag Identity)@, then @Rec ==> AnInt ==> 3 + 4@
-- is parsed as would be expected (@Rec ==> (AnInt ==> (3 + 4))@) and has type
-- @DSum Identity Tag@.  Its precedence is just above that of '$', so
-- @foo bar $ AString ==> "eep"@ is equivalent to @foo bar (AString ==> "eep")@.
data DSum c tag f = forall a. (c a) =>  !(tag a) :=> f a
#if MIN_VERSION_base(4,7,0)
    deriving Typeable
#endif
infixr 1 :=>, ==>

(==>) :: Applicative f => c a => tag a -> a -> DSum c tag f
k ==> v = k :=> pure v

-- |In order to make a 'Show' instance for @DSum tag f@, @tag@ must be able
-- to show itself as well as any value of the tagged type.  'GShow' together
-- with this class provides the interface by which it can do so.
--
-- @ShowTag tag f => t@ is conceptually equivalent to something like this
-- imaginary syntax:  @(forall a. Inhabited (tag a) => Show (f a)) => t@,
-- where 'Inhabited' is an imaginary predicate that characterizes 
-- non-empty types, and 'f' and 'a' do not occur free in 't'.
--
-- The @Tag@ example type introduced in the 'DSum' section could be given the
-- following instances, among others:
-- 
-- > instance GShow Tag where
-- >     gshowsPrec _p AString = showString "AString"
-- >     gshowsPrec _p AnInt   = showString "AnInt"
-- > instance ShowTag Tag [] where
-- >     showTaggedPrec AString = showsPrec
-- >     showTaggedPrec AnInt   = showsPrec
-- 
class GShow tag => ShowTag tag f where
    -- |Given a value of type @tag a@, return the 'showsPrec' function for 
    -- the type @f a@.
    showTaggedPrec :: tag a -> Int -> f a -> ShowS

instance Show (f a) => ShowTag ((:=) a) f where
    showTaggedPrec Refl = showsPrec

-- This instance is questionable.  It works, but is pretty useless.
instance Show (f a) => ShowTag (GOrdering a) f where
    showTaggedPrec GEQ = showsPrec
    showTaggedPrec _   = \p _ -> showParen (p > 10)
        ( showString "error "
        . shows "type information lost into the mists of oblivion"
        )

instance ShowTag tag f => Show (DSum c tag f) where
    showsPrec p (tag :=> value) = showParen (p >= 10)
        ( gshowsPrec 0 tag
        . showString " :=> "
        . showTaggedPrec tag 1 value
        )

class GRead tag => ReadTag tag f where
    readTaggedPrec :: tag a -> Int -> ReadS (f a)

-- |In order to make a 'Read' instance for @DSum tag f@, @tag@ must be able
-- to parse itself as well as any value of the tagged type.  'GRead' together
-- with this class provides the interface by which it can do so.
--
-- @ReadTag tag f => t@ is conceptually equivalent to something like this
-- imaginary syntax:  @(forall a. Inhabited (tag a) => Read (f a)) => t@,
-- where 'Inhabited' is an imaginary predicate that characterizes 
-- non-empty types, and 'f' and 'a' do not occur free in 't'.
--
-- The @Tag@ example type introduced in the 'DSum' section could be given the
-- following instances, among others:
-- 
-- > instance GRead Tag where
-- >     greadsPrec _p str = case tag of
-- >        "AString"   -> [(\k -> k AString, rest)]
-- >        "AnInt"     -> [(\k -> k AnInt,   rest)]
-- >        _           -> []
-- >        where (tag, rest) = break isSpace str
-- > instance ReadTag Tag [] where
-- >     readTaggedPrec AString = readsPrec
-- >     readTaggedPrec AnInt   = readsPrec
-- 
instance Read (f a) => ReadTag ((:=) a) f where
    readTaggedPrec Refl = readsPrec

-- This instance is questionable.  It works, but is partial (and is also pretty useless)
-- instance Read a => ReadTag (GOrdering a) where
--     readTaggedPrec GEQ = readsPrec
--     readTaggedPrec tag = \p -> readParen (p>10) $ \s ->
--         [ (error msg, rest')
--         | let (con, rest) = splitAt 6 s
--         , con == "error "
--         , (msg, rest') <- reads rest :: [(String, String)]
--         ]
{-
instance ReadTag tag f => Read (DSum tag f) where
    readsPrec p = readParen (p > 1) $ \s -> 
        concat
            [ getGReadResult withTag $ \tag ->
                [ (tag :=> val, rest'')
                | (val, rest'') <- readTaggedPrec tag 1 rest'
                ]
            | (withTag, rest) <- greadsPrec p s
            , let (con, rest') = splitAt 5 rest
            , con == " :=> "
            ]
-}
-- |In order to test @DSum tag f@ for equality, @tag@ must know how to test
-- both itself and its tagged values for equality.  'EqTag' defines
-- the interface by which they are expected to do so.
-- 
-- Continuing the @Tag@ example from the 'DSum' section, we can define:
-- 
-- > instance GEq Tag where
-- >     geq AString AString = Just Refl
-- >     geq AnInt   AnInt   = Just Refl
-- >     geq _       _       = Nothing
-- > instance EqTag Tag [] where
-- >     eqTagged AString AString = (==)
-- >     eqTagged AnInt   AnInt   = (==)
-- 
-- Note that 'eqTagged' is not called until after the tags have been
-- compared, so it only needs to consider the cases where 'gcompare' returns 'GEQ'.
class GEq tag => EqTag tag f where
    -- |Given two values of type @tag a@ (for which 'gcompare' returns 'GEQ'),
    -- return the '==' function for the type @f a@.
    eqTagged :: tag a -> tag a -> f a -> f a -> Bool

instance Eq (f a) => EqTag ((:=) a) f where
    eqTagged Refl Refl = (==)

instance EqTag tag f => Eq (DSum c tag f) where
    (t1 :=> x1) == (t2 :=> x2)  = fromMaybe False $ do
        Refl <- geq t1 t2
        return (eqTagged t1 t2 x1 x2)

-- |In order to compare @DSum tag f@ values, @tag@ must know how to compare
-- both itself and its tagged values.  'OrdTag' defines the 
-- interface by which they are expected to do so.
-- 
-- Continuing the @Tag@ example from the 'EqTag' section, we can define:
-- 
-- > instance GCompare Tag where
-- >     gcompare AString AString = GEQ
-- >     gcompare AString AnInt   = GLT
-- >     gcompare AnInt   AString = GGT
-- >     gcompare AnInt   AnInt   = GEQ
-- > instance OrdTag Tag [] where
-- >     compareTagged AString AString = compare
-- >     compareTagged AnInt   AnInt   = compare
-- 
-- As with 'eqTagged', 'compareTagged' only needs to consider cases where
-- 'gcompare' returns 'GEQ'.
class (EqTag tag f, GCompare tag) => OrdTag tag f where
    -- |Given two values of type @tag a@ (for which 'gcompare' returns 'GEQ'),
    -- return the 'compare' function for the type @f a@.
    compareTagged :: tag a -> tag a -> f a -> f a -> Ordering

instance Ord (f a) => OrdTag ((:=) a) f where
    compareTagged Refl Refl = compare

instance OrdTag tag f => Ord (DSum c tag f) where
    compare (t1 :=> x1) (t2 :=> x2)  = case gcompare t1 t2 of
        GLT -> LT
        GGT -> GT
        GEQ -> compareTagged t1 t2 x1 x2
