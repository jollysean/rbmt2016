import Control.Exception.Lifted as L (catch)
import Data.Char (isSpace)
import Data.List (delete,intercalate)
import Debug.Trace
import qualified Data.Map as M
import System.Environment
import System.IO 
import System.Process
import Control.Monad.Trans.State.Lazy
import Control.Monad.IO.Class
import Control.Monad (forever)
import PGF2
import qualified Data.Map as Map

main = getPGF =<< getArgs

getPGF [path] = pgfShell =<< readPGF path
getPGF _ = putStrLn "Usage: pgf-shell <path to pgf>"

pgfShell pgf =
  do putStrLn . unwords . M.keys $ languages pgf
     flip evalStateT (pgf,[]) $ forever $ do puts (abstractName pgf ++ "> "); liftIO $ hFlush stdout
                                             execute =<< liftIO readLn

isr (Right foo) = True
isr _           = False

execute cmd =
  case cmd of
    L lang tree -> do pgf <- gets fst
                      c <- getConcr' pgf lang
                      put (pgf,[])
                      putln $ linearize c tree

    POmorfi rs  -> do ss <- sequence `fmap` sequence [ liftIO $ analyse wd | wd <- words rs ]
                      mapM_ (execute . P "LangFin") (map unwords ss)

    P lang s    -> do pgf <- gets fst
                      c <- getConcr' pgf lang
                      case parse c (startCat pgf) s of
                        Left tok -> do put (pgf,[])
                                       --putln ("Parse error: "++tok)
                        Right ts -> do put (pgf,map show ts)
                                       putln s
                                       pop
    T from to s -> do pgf <- gets fst
                      cfrom <- getConcr' pgf from
                      cto   <- getConcr' pgf to
                      case parse cfrom (startCat pgf) s of
                        Left tok -> do put (pgf,[])
                                       putln ("Parse error: "++tok)
                        Right ts -> do put (pgf,map (linearize cto.fst) ts)
                                       pop
    I path -> do pgf <- liftIO (readPGF path)
                 putln . unwords . M.keys $ languages pgf
                 put (pgf,[])
    Empty -> pop
    Unknown s -> putln ("Unknown command: "++s)       
      `L.catch` (liftIO . print . (id::IOError->IOError))


pop = do (pgf,ls) <- get
         let (ls1,ls2) = splitAt 1 ls
         putl ls1
         put (pgf,ls2)

--getConcr' :: PGF -> ConcName -> m Concr
getConcr' pgf lang =
    maybe (fail $ "Concrete syntax not found: "++show lang) return $
    Map.lookup lang (languages pgf)

printl xs = liftIO $ putl $ map show xs
putl ls = liftIO . putStr $ unlines ls
putln s = liftIO $ putStrLn s
puts s = liftIO $ putStr s

--------------------------------------------------------------------------------


omorfi :: Bool -> FilePath -> String -> IO [String]
omorfi isAna transducer word = do
  (_, Just out1, _, _) <-
      createProcess (proc "echo" [word]){std_out=CreatePipe}
  (_, Just out2, _, _) <- 
      createProcess (proc "hfst-lookup" [transducer]){std_in=UseHandle out1
                                      , std_out=CreatePipe}
  let f = if isAna then gf2ftb else gf2ftb
  result <- (filter (not.null) . lines) `fmap` hGetContents' out2
  
  mapM_ putStrLn (map ("omorfi: " ++) result)
  mapM_ hClose [out1,out2]
  return $ word:map f result

analyse = omorfi True "omorfi-ftb3.analyse.hfst"
generate = omorfi False "omorfi-ftb3.generate.hfst"


gf2ftb :: String -> String
gf2ftb ana = intercalate "+" lemmaNParPl
  where (_wf:anas:_prob) = split' (=='\t') ana
        lemmaNParPl = words anas


--------------------------------------------------------------------------------


-- Strict hGetContents
hGetContents' :: Handle -> IO String
hGetContents' hdl = do e <- hIsEOF hdl
                       if e then return []
                            else do c <- hGetChar hdl
                                    cs <- hGetContents' hdl
                                    return (c:cs)

split :: Char -> String -> (String,String)
split c str = if atLeast 2 res then (res !! 0, res !! 1) else (":(", "D:")
  where res = split' (==c) str


split' :: (a -> Bool) -> [a] -> [[a]]
split' p [] = []
split' p xs = takeWhile (not . p) xs : split' p (drop 1 (dropWhile (not . p) xs))

atLeast 0 _  = True
atLeast _ [] = False
atLeast k (x:xs) = atLeast (k-1) xs

--------------------------------------------------------------------------------

-- | Abstracy syntax of shell commands
data Command = P String String | POmorfi String | L String Expr | T String String String
             | I FilePath | Empty | Unknown String
             deriving Show

-- | Shell command parser
instance Read Command where
  readsPrec _ s =
      take 1 $
          [(P l r2,"") | ("p",r1)<-lex s, (l,r2) <- lex r1]
       ++ [(POmorfi r1,"") | ("po",r1)<-lex s]
       ++ [(L l t,"") | ("l",r1)<-lex s, (l,r2)<- lex r1, Just t<-[readExpr r2]]
       ++ [(T l1 l2 r3,"") | ("t",r1)<-lex s, (l1,r2)<-lex r1, (l2,r3)<-lex r2]
       ++ [(I (dropWhile isSpace r),"") | ("i",r)<-lex s]
       ++ [(Empty,"") | ("","") <- lex s]
       ++ [(Unknown s,"")]
