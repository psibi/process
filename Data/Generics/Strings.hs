-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Generics.Strings
-- Copyright   :  (c) The University of Glasgow, CWI 2001--2003
-- License     :  BSD-style (see the file libraries/base/LICENSE)
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  experimental
-- Portability :  non-portable
--
-- "Scrap your boilerplate" --- Generic programming in Haskell 
-- See <http://www.cs.vu.nl/boilerplate/>.
--
-----------------------------------------------------------------------------

module Data.Generics.Strings ( 

	-- * Generic operations for string representations of terms
	gshow,
	gread

 ) where

------------------------------------------------------------------------------

import Control.Monad
import Data.Maybe
import Data.Typeable
import Data.Generics.Basics
import Data.Generics.Aliases



-- | Generic show: an alternative to \"deriving Show\"
gshow :: Data a => a -> String

-- This is a prefix-show using surrounding "(" and ")",
-- where we recurse into subterms with gmapQ.
-- 
gshow = ( \t ->
                "("
             ++ conString (toConstr t)
             ++ concat (gmapQ ((++) " " . gshow) t)
             ++ ")"
        ) `extQ` (show :: String -> String)


-- | The type constructor for gunfold a la ReadS from the Prelude;
--   we don't use lists here for simplicity but only maybes.
--
newtype GRead a = GRead (String -> Maybe (a, String)) deriving Typeable
unGRead (GRead x) = x


-- | Turn GRead into a monad.
instance Monad GRead where
  return x = GRead (\s -> Just (x, s))
  (GRead f) >>= g = GRead (\s -> 
                             maybe Nothing 
                                   (\(a,s') -> unGRead (g a) s')
                                   (f s)
                          )

instance MonadPlus GRead where
 mzero = GRead (\_ -> Nothing)
 mplus = undefined


-- | Special parsing operators
trafo f = GRead (\s -> Just ((), f s))
query f = GRead (\s -> if f s then Just ((), s) else Nothing)


-- | Generic read: an alternative to \"deriving Read\"
gread :: Data a => String -> Maybe (a, String)

{-

This is a read operation which insists on prefix notation.  (The
Haskell 98 read deals with infix operators subject to associativity
and precedence as well.) We use gunfoldM to "parse" the input. To be
precise, gunfoldM is used for all types except String. The
type-specific case for String uses basic String read.

-}


gread = unGRead gread' 

 where

  gread' :: GenericB GRead
  gread' = gdefault `extB` scase

   where

    -- a specific case for strings
    scase = GRead ( \s -> case reads s of
                            [x::(String,String)] -> Just x
                            _ -> Nothing
                  ) 

    -- the generic default for gread
    gdefault = 
      do 
  	trafo $  dropWhile ((==) ' ')
	query $  not . (==) ""
	query $  (==) '(' . head
	trafo $  tail
	trafo $  dropWhile ((==) ' ')                
	str   <- parseConstr
        con   <- str2con str
        x     <- gunfoldM con gread'
	trafo $  dropWhile ((==) ' ')
	query $  not . (==) ""
	query $  (==) ')' . head
	trafo $  tail
        return x

     where
       -- Turn string into constructor driven by gdefault's type
       str2con = maybe mzero return
               .
	         (    stringCon		-- look up constructor at hand
                    $ dataTypeOf	-- get handle on all constructurs
                    $ undefinedType	-- turn type value into undefined
                    $ paraType		-- get a handle on a in m a
                    $ gdefault		-- use as type argument
                 )
{-
  foo = 
    do s' <- return $ dropWhile ((==) ' ') s
       guard (not (s' == ""))
       guard (head s' == '(')
       (c,s'')  <- parseConstr (dropWhile ((==) ' ') (tail s'))
       u  <- return undefined 
       dt <- return $ dataTypeOf u
       case stringCon dt c of
        Nothing -> error "Data.Generics.String: gread failed"
        Just c' -> 
          gunfoldm c' gread

       guard ( or [ maxConIndex (dataTypeOf u) == 0
                  , c `elem` constrsOf u
                  ]
             )
       (a,s''') <- unGRead (gunfold f z c) s''
       _ <- return $ constrainTypes a u
       guard (not (s''' == "")) 
       guard (head s''' == ')')
       return (a, tail s''')
-}

  -- Get a Constr's string at the front of an input string
  parseConstr :: GRead String

  parseConstr = GRead ( \s -> case s of

    -- Infix operators are prefixed in parantheses
    ('(':s) -> case break ((==) ')') s of
                 (s'@(_:_),(')':s'')) -> Just ("(" ++ s' ++ ")", s'')
                 _ -> Nothing

    -- Special treatment of multiple token constructors
    ('[':']':s) -> Just ("[]",s)

    -- Try lex for ordinary constructor and basic datatypes
    s -> case lex s of
           [(s'@(_:_),s'')] -> Just (s',s'')
           _ -> Nothing

    )

