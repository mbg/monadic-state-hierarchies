module Language.Hoop.Constructor where

import Language.Haskell.TH
import Language.Haskell.TH.Syntax

data StateCtr = SCtr {
    sctrDec   :: Dec,
    sctrTypes :: [Type]
}