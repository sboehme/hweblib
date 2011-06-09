{-# LANGUAGE 
    OverloadedStrings
  , PackageImports
  #-}

module Network.Parser.Rfc2616 where

import Control.Applicative hiding (many)
import Data.Attoparsec
import Data.Attoparsec.FastSet (memberWord8, fromList)
import Data.Attoparsec.Char8 (stringCI)
import Data.ByteString as W hiding (concat)
import Data.ByteString.Char8 as C hiding (concat)
import Data.ByteString.Internal (c2w)
import Data.Word (Word8())
import Prelude hiding (take, takeWhile)
import qualified Network.Parser.Rfc3986 as R3986
import Network.Parser.RfcCommon
import Network.Parser.Rfc2234
import Data.List
-- | Basic Parser Constructs for RFC 2616

separators_pred, token_pred
 :: Word8 -> Bool

token_pred w = char_pred w && not (ctl_pred w || separators_pred w)
token :: Parser [Word8]
token = many1 $ satisfy token_pred
{-# INLINE token #-}

-- "()<>@,;:\\\"/[]?={} \t"
separatorSet :: [Word8]
separatorSet = [40,41,60,62,64,44,59,58,92,34,47,91,93,63,61,123,125,32,9]
separators_pred w = memberWord8 w (fromList separatorSet)
separators :: Parser Word8
separators = satisfy separators_pred
{-# INLINE separators #-}

comment :: Parser [Word8]
comment = do 
  word8 40 
  r <- concat <$> many (quotedPair <|> ((:[]) <$> ctext))
  word8 41
  return r

-- parse (httpVersion) (W.pack "HTTP/12.15\n")
httpVersion :: Parser HttpVersion
httpVersion = stringCI "http/" *> 
              ((,) <$> (num <* sep) <*> num)
 where num = many1 digit >>= return . read . C.unpack . W.pack
       sep = word8 . c2w $ '.'


-- parse (method) (W.pack "GET /")
method :: Parser Method
method = (GET         <$ stringCI "get")
         <|> (PUT     <$ stringCI "put")
         <|> (POST    <$ stringCI "post")
         <|> (HEAD    <$ stringCI "head")
         <|> (DELETE  <$ stringCI "delete")
         <|> (TRACE   <$ stringCI "trace")
         <|> (CONNECT <$ stringCI "connect")
         <|> (OPTIONS <$ stringCI "options")
         <|> ((EXTENSIONMETHOD . W.pack) <$> token)

requestUri = try (Asterisk <$ word8 42)
             <|> AbsoluteUri <$> R3986.absoluteUri
             <|> (AbsolutePath . W.pack) <$> R3986.pathAbsolute
             <|> Authority <$> R3986.authority 

requestLine :: Parser (Method, RequestUri, HttpVersion)
requestLine = ret <$> method      <* sp
                  <*> requestUri  <* sp
                  <*> httpVersion <* crlf
    where ret m u h = (m,u,h)

headerContentNc_pred w 
       = (w >= 0x00 && w <= 0x08)
      || (w >= 0x0b && w <= 0x0c)
      || (w >= 0x0e && w <= 0x1f)
      || (w >= 0x21 && w <= 0x39)
      || (w >= 0x3b && w <= 0xff)

headerContent = satisfy (\w -> headerContentNc_pred w || w == 58) -- ':'
headerName = many1 $ satisfy headerContentNc_pred
headerValue = do
  c <- headerContent
  r <- option [] (many (headerContent <|> lws)) -- TODO: http://stuff.gsnedders.com/http-parsing.txt
  return (c:r)

header :: Parser (ByteString,ByteString)
header = ret <$> headerName  <* (word8 58 <* lwss)
             <*> headerValue <* lwss
    where ret n v = (W.pack n, W.pack v)

entityBody = many octet
messageBody = entityBody

request = do
  (m, ru, v) <- requestLine 
  hdrs <- many (header <* crlf)
  crlf
--  body <- option [] messageBody
  return $ Request
             { rqMethod  = m
             , rqUri     = ru
             , rqVersion = v
             , rqHeaders = hdrs
             , rqBody    = W.empty -- W.pack body
             }

-- data HttpMessage = Request | Response
data Header = GeneralHeader | RequestHeader | EntityHeader

data Request = Request
    { rqMethod  :: Method
    , rqUri     :: RequestUri
    , rqVersion :: (Int, Int)
    , rqHeaders :: [(ByteString, ByteString)]
    , rqBody    :: ByteString 
    } deriving (Eq, Show)

type HttpVersion = (Int,Int)
data Method = GET | HEAD | POST | PUT | DELETE 
            | TRACE | OPTIONS | CONNECT 
            | EXTENSIONMETHOD ByteString
              deriving (Show,Read,Ord,Eq)

data RequestUri = Asterisk 
                | AbsoluteUri R3986.URI
                | AbsolutePath ByteString
                | Authority (Maybe R3986.URIAuth)
                  deriving (Eq, Show)