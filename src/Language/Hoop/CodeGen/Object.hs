module Language.Hoop.CodeGen.Object where

import Language.Haskell.TH
import Language.Haskell.TH.Syntax

import Language.Hoop.StateDecl
import Language.Hoop.CodeGen.Shared
import Language.Hoop.CodeGen.Interop

ns :: Bang
ns = Bang SourceNoUnpack NoSourceStrictness

supField :: String -> Type -> VarBangType
supField c pt = (fname, ns, ftype)
    where
        fname = mkName $ "_" ++ c ++ "_sup"
        ftype = pt

dataField :: String -> [String] -> VarStrictType
dataField c vars = (fname, ns, ftype)
    where
        fname = mkName $ "_" ++ c ++ "_data"
        ftype = appN (ConT $ mkName $ c ++ "State") vars

subField :: String -> Name -> [String] -> VarStrictType
subField c s vars = (fname, ns, ftype)
    where
        fname = mkName $ "_" ++ c ++ "_sub"
        ftype = appN (VarT s) vars

objectCtrCxt :: String -> [String] -> Name -> Name -> Q Cxt
objectCtrCxt name vars s d = do
    let
        clname = mkName $ name ++ "Like"
        tyname = mkName $ name ++ "M"
        ty     = appN (ConT tyname) vars
        tyvars = map (VarT . mkName) vars
    return [foldl AppT (ConT clname) ([VarT s, VarT d, ty] ++ tyvars)]

dataCtr :: String -> [String] -> Q Con
dataCtr name vars = do
    let
        cname = mkName $ name ++ "Data"
    return $ RecC cname [dataField name vars]

startCtr :: String -> [String] -> Q Con
startCtr name vars = do
    s   <- newName "s"
    d   <- newName "d"
    cxt <- objectCtrCxt name vars s d
    let
        cname = mkName $ name ++ "Start"
    return $ ForallC [PlainTV s, PlainTV d] cxt $ RecC cname [
        dataField name vars,
        subField name s vars]

endCtr :: String -> [String] -> Type -> Q Con
endCtr name vars p = do
    let
        cname = mkName $ name ++ "End"
    return $ RecC cname [
        supField name p,
        dataField name vars]

middleCtr :: String -> [String] -> Type -> Q Con
middleCtr name vars p  = do
    s   <- newName "s"
    d   <- newName "d"
    cxt <- objectCtrCxt name vars s d
    let
        cname = mkName $ name ++ "Middle"
    return $ ForallC [PlainTV s, PlainTV d] cxt $ RecC cname [
        supField name p,
        dataField name vars,
        subField name s vars]

genObjectCtrs :: StateDecl -> Q [Con]
genObjectCtrs (StateDecl {
    stateMod = m,
    stateName = name,
    stateParams = vars,
    stateParent = Nothing}) = do
        dctr <- dataCtr name vars
        case m of
            Just Final -> return [dctr]
            _          -> do
                sctr <- startCtr name vars
                return [dctr, sctr]
genObjectCtrs (StateDecl {
    stateMod = m,
    stateName = name,
    stateParams = vars,
    stateParentN = (Just p),
    stateParentPs = ps } ) = do
        let pt = appN (parseType p) ps
        sctr <- startCtr name vars
        mctr <- middleCtr name vars pt
        dctr <- dataCtr name vars
        ectr <- endCtr name vars pt
        case m of
            Nothing       -> return [dctr, sctr, ectr, mctr]
            Just Abstract -> return [sctr, ectr, mctr]
            Just Final    -> return [dctr, ectr]

-- | Generates the object type for a state declaration
genStateObject :: [TyVarBndr] -> StateDecl -> Q Dec
genStateObject tyvars s@(StateDecl { stateName = name }) = do
    let
        -- unlike in the paper, we use just the name for the object
        oname = mkName $ name {- ++ "Object" -}
    cs <- genObjectCtrs s
    return $ DataD [] oname tyvars Nothing cs []
