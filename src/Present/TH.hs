{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Generate a @present@ function for a type.

module Present.TH where

import Present.Types

import Data.Proxy
import Language.Haskell.TH as TH
import Language.Haskell.TH.Lift ()
import Prelude hiding (head)

-- -- | Make instances for all
-- makePresents :: Type -> Q [Dec]
-- makePresents

-- | Make a 'Show'-based instance of 'Present' for decimals.
makeDecimalPresent :: Name -> Q [Dec]
makeDecimalPresent name =
  [d|instance Present $(conT name) where
       presentValue _mode _ _ i =
         Decimal (presentType (return i))
                 (show i)
       presentType _ = ConT name|]

-- | Make a 'Show'-based instance of 'Present' for integrals.
makeIntegralPresent :: Name -> Q [Dec]
makeIntegralPresent name =
  [d|instance Present $(conT name) where
       presentValue _mode _ _ i =
         Integral (presentType (return i))
                  (fromIntegral i)
       presentType _ = ConT name|]

-- | Make an instance for 'Present' for the given type.
makeGenericPresent :: Name -> Q [Dec]
makeGenericPresent name =
  do info <- reify name
     case info of
       TyConI dec ->
         case dec of
           DataD _ cname tyvars cons _names ->
             fmap return
                  (makeInstance cname
                                (vars tyvars)
                                cons)
           NewtypeD _ cname tyvars con _names ->
             fmap return
                  (makeInstance cname
                                (vars tyvars)
                                [con])
           _ ->
             error ("Need a name for a type: " ++ show dec)
       _ -> error "Need a type name."
  where vars tyvars =
          zipWith (\i _ ->
                     varT (mkName ("a" ++ show i)))
                  [1 :: Integer ..]
                  tyvars

-- | Make an instance declaration for 'Present-.
makeInstance :: Name -> [Q TH.Type] -> [Con] -> Q Dec
makeInstance name vars cons =
  instanceD ctx head [makePresentValue cons,makePresentType name vars]
  where ctx =
          sequence (map (classP ''Present .
                         return)
                        vars)
        head =
          appT (conT ''Present)
               (foldl appT (conT name) vars)

-- | Make the 'presentValue' method.
makePresentValue :: [Con] -> Q Dec
makePresentValue cons =
  let value = mkName "value"
      hierarchy = mkName "h"
      pid = mkName "pid"
      mode = mkName "mode"
  in funD 'presentValue
          [clause [varP mode,varP hierarchy,varP pid,varP value]
                  (normalB (caseE (varE value)
                                  (map (makeAlt mode hierarchy value) cons)))
                  []]

-- | Make the 'presentType' method.
makePresentType :: Name -> [TypeQ] -> DecQ
makePresentType name vars =
  funD 'presentType
       [clause (if null vars
                   then [wildP]
                   else [varP proxy])
               (normalB (foldl (\x y ->
                                  [|AppT $(x)
                                         $(y)|])
                               [|ConT name|]
                               (map makeTyVarRep vars)))
               []]
  where proxy = mkName "proxy"
        makeTyVarRep var =
          let needle = mkName "needle"
          in letE [sigD needle
                        (appT (appT tyFun
                                    (appT (conT ''Proxy)
                                          (foldl appT (conT name) vars)))
                              (appT (conT ''Proxy) var))
                  ,valD (varP needle)
                        (normalB (lamE [wildP]
                                       (conE 'Proxy)))
                        []]
                  (appE (varE 'presentType)
                        (appE (varE needle)
                              (varE proxy)))

-- | Because I didn't see a better way anywhere.
tyFun :: Q Type
tyFun = [t|(->)|]

-- | Make the alt for presenting a constructor.
makeAlt :: Name -> Name -> Name -> Con -> Q Match
makeAlt mode h value (RecC name slots) =
  match (conP name (map varP pvars))
        (normalB [|case $(varE (mkName "pid")) of
                     Cursor [] ->
                       Alg (presentType (return $(varE value)))
                           name
                           $(listE (zipWith (\i var ->
                                               tupE [[|presentType (return $(varE var))|]
                                                    ,[|Cursor (return $(litE (integerL i)))|]])
                                            [0 ..]
                                            pvars))
                     Cursor (i:j) ->
                       $(if null pvars
                            then [|error ("Unexpected case for Present: " ++
                                          $(litE (stringL (show name))) ++
                                          "Index: " ++
                                          show (i,j))|]
                            else caseE [|i|]
                                       (zipWith (\ij var ->
                                                   (match (if ij ==
                                                              fromIntegral (length pvars) -
                                                              1
                                                              then wildP
                                                              else litP (integerL ij))
                                                          (normalB [|presentValue $(varE mode)
                                                                                  $(varE h)
                                                                                  (Cursor j)
                                                                                  $(varE var)|])
                                                          []))
                                                [0 ..]
                                                pvars))|])
        []
  where pvars =
          zipWith makeSlot [1 :: Integer ..] slots
        makeSlot x _ = mkName ("slot" ++ show x)
makeAlt mode h value (NormalC name slots) =
  match (conP name (map varP pvars))
        (normalB [|case $(varE (mkName "pid")) of
                     Cursor [] ->
                       Alg (presentType (return $(varE value)))
                           name
                           $(listE (zipWith (\i var ->
                                               tupE [[|presentType (return $(varE var))|]
                                                    ,[|Cursor (return $(litE (integerL i)))|]])
                                            [0 ..]
                                            pvars))
                     Cursor (i:j) ->
                       $(if null pvars
                            then [|error ("Unexpected case for Present: " ++
                                          $(litE (stringL (show name))) ++
                                          "Index: " ++
                                          show (i,j))|]
                            else caseE [|i|]
                                       (zipWith (\ij var ->
                                                   (match (if ij ==
                                                              fromIntegral (length pvars) -
                                                              1
                                                              then wildP
                                                              else litP (integerL ij))
                                                          (normalB [|presentValue $(varE mode)
                                                                                  $(varE h)
                                                                                  (Cursor j)
                                                                                  $(varE var)|])
                                                          []))
                                                [0 ..]
                                                pvars))|])
        []
  where pvars =
          zipWith makeSlot [1 :: Integer ..] slots
        makeSlot x _ = mkName ("slot" ++ show x)
makeAlt mode h value (InfixC slot1 name slot2) =
  makeAlt mode h value (NormalC name [slot1,slot2])
makeAlt _ _ _ c = error ("makePresent.makeAlt: Unexpected case: " ++ show c)
