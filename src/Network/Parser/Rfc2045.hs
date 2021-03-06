{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      :  Network.Parser.2045
-- Copyright   :  Aycan iRiCAN 2010-2015
-- License     :  BSD3
--
-- Maintainer  :  iricanaycan@gmail.com
-- Stability   :  experimental
-- Portability :  unknown
--
-- Multipurpose Internet Mail Extensions (MIME) Part One:
-- Format of Internet Message Bodies
-- <http://www.ietf.org/rfc/rfc2045.txt>

module Network.Parser.Rfc2045 where
--------------------------------------------------------------------------------
import           Control.Applicative
import           Control.Monad                    (join)
import           Data.Attoparsec.ByteString
import           Data.Attoparsec.ByteString.Char8 (decimal, stringCI)
import           Data.ByteString
import           Data.Map.Strict                  as M hiding (singleton)
import           Data.Monoid
import           Data.Word                        (Word8)
--------------------------------------------------------------------------------
import           Network.Parser.Rfc2234
import           Network.Parser.Rfc2822           (msg_id, quoted_string, text)
--------------------------------------------------------------------------------
-- TODO: implement fields of rfc 822

-- TODO: we don't support comments on header values "MIME-Version:
-- 1.(produced by MetaSend Vx.x)0" which we should parse and ignore.


-- * 3. MIME Header Fields

--mimePartHeaders = ret <$> entityHeaders <*> option [] fields
--  where ret eh f = ...
mimePartHeaders :: Parser [Header]
mimePartHeaders = entityHeaders

-- mimeMessageHeaders = ret <$> entityHeaders <*> fields <*> (version <* crlf)
--  where ret eh f v =

entityHeaders :: Parser [Header]
entityHeaders = many entityHeader

entityHeader :: Parser Header
entityHeader  =   (version            <* crlf)
              <|> (content            <* crlf)
              <|> (encoding           <* crlf)
              <|> (description        <* crlf)
              <|> (contentId          <* crlf)
              <|> (mimeExtensionField <* crlf)

-- * 4.  MIME-Version Header Field

version :: Parser Header
version = ret <$> (stringCI "mime-version" *> colonsp *> decimal) -- ':'
          <*> (word8 46 *> decimal) -- '.'
    where ret a b = Header VersionH (pack [a+48,46,b+48]) M.empty

-- * 5. Content-Type Header Field

ietf_token :: Parser ByteString
ietf_token = Control.Applicative.empty

iana_token :: Parser ByteString
iana_token = Control.Applicative.empty

tspecialsPred :: Word8 -> Bool
tspecialsPred = inClass "()<>@,;:\\\"/[]?="

tspecials :: Parser Word8
tspecials = satisfy tspecialsPred

tokenPred :: Word8 -> Bool
tokenPred w = charPred w && not (w == 32 || ctlPred w || tspecialsPred w)

token :: Parser [Word8]
token = many1 $ satisfy tokenPred

attribute :: Parser [Word8]
attribute = token

parameter :: Parser (ByteString, ByteString)
parameter = res <$> (attribute <* word8 61) <*> value
    where res a v = (pack a, v)

x_token :: Parser ByteString
x_token = stringCI "x-" *> (pack <$> many1 (satisfy x_token_pred))
  where
    x_token_pred :: Word8 -> Bool
    x_token_pred w = tokenPred w && (w /= 32)

value :: Parser ByteString
value = (pack <$> token) <|> quoted_string

-- discrete and composite types are a little bit different from BNF
-- definitions in order to keep code flow clean.
mtype :: Parser ByteString
mtype = stringCI "multipart"
        <|> stringCI "text"
        <|> stringCI "image"
        <|> stringCI "audio"
        <|> stringCI "video"
        <|> stringCI "application"
        <|> stringCI "message"
        <|> extensionToken

-- TODO: subtype = extensionToken <|> iana_token
subtype :: Parser ByteString
subtype = pack <$> token

-- TODO: extensionToken = x_token <|> ietf_token
extensionToken :: Parser ByteString
extensionToken = x_token

-- >>> parseOnly content "Content-type: text/plain; charset=us-ascii\n"
-- Right (Header {hType = ContentH, hValue = "textplain", hParams = fromList [("charset","us-ascii")]})
-- >>> let a = parseOnly content "Content-type: text/plain; charset=us-ascii\n"
-- >>>     b = parseOnly content "Content-type: text/plain; charset=\"us-ascii\"\n"
-- >>> in a == b
-- True
content :: Parser Header
content
  = do ty <- (\a b -> a <> "/" <> b) <$> (stringCI "content-type" *> colonsp *> mtype) <* word8 47 <*> subtype
       ps <-  many (semicolonsp *> parameter)
       return $ Header ContentH ty (M.fromList ps)

-- * 6. Content-Transfer-Encoding Header Type

encoding :: Parser Header
encoding = ret <$> (stringCI "content-transfer-encoding" *> colonsp *> mechanism)
    where ret m = Header EncodingH m M.empty

mechanism :: Parser ByteString
mechanism = stringCI "7bit"
            <|> stringCI "8bit"
            <|> stringCI "binary"
            <|> stringCI "quoted-printable"
            <|> stringCI "base64"
            <|> x_token <|> ietf_token

-- * Quoted Printable

safe_char :: Parser Word8
safe_char = satisfy (\w -> (w >= 33 && w <= 60) || (w >= 62 && w <= 126))

hexOctet :: Parser Word8
hexOctet = ret <$> (word8 61 *> hexdig) <*> hexdig
    where ret a b = toTen a * 16 + toTen b
          toTen w | w >= 48 && w <= 57  =  fromIntegral (w - 48)
                  | w >= 97 && w <= 102 =  fromIntegral (w - 87)
                  | otherwise           =  fromIntegral (w - 55)
-- >>> let message = "aaaa    \nbbbb"
-- >>> parse (many (AC.char 'a') <* transportPadding) message
-- Done "\nbbbb" "aaaa"
transportPadding :: Parser ()
transportPadding = lwsp >> return ()

ptext :: Parser Word8
ptext = hexOctet <|> safe_char

qp_section :: Parser [Word8]
qp_section = many (ptext <|> sp <|> ht)

qp_segment :: Parser [Word8]
qp_segment = ret <$> qp_section <*> many (sp <|> ht) <*> word8 61
    where ret a [] _ = a
          ret a _  _ = a ++ [32]

qp_part :: Parser [Word8]
qp_part = qp_section

qp_line :: Parser [Word8]
qp_line = do
  a <- many $ (++) <$> qp_segment <*> (transportPadding *> crlf >>= return . (:[]))
  b <- qp_part <* transportPadding
  return $ join a ++ b

quoted_printable :: Parser ByteString
quoted_printable = ret <$> qp_line <*> many (crlf *> qp_line)
  where ret x xs = pack (x ++ join xs)

-- * 7.  Content-ID Header Field
contentId :: Parser Header
contentId = ret <$> (stringCI "content-id" *> colonsp *> msg_id)
    where ret i = Header IdH i M.empty

-- * 8.  Content-Description Header Field
-- TODO: support 2047 encoding
description :: Parser Header
description = ret <$> (stringCI "content-description" *> colonsp *> many text)
    where ret d = Header DescriptionH (pack d) M.empty

-- * 9. Additional MIME Header Fields
-- TODO: support 822 header fields
mimeExtensionField :: Parser Header
mimeExtensionField = do
  k <- stringCI "content-" *> token
  v <- colonsp *> many text
  return $ Header (ExtensionH $ pack k) (pack v) M.empty

-- * Utilities
colonsp :: Parser ()
colonsp = word8 58 *> lwsp *> pure ()

semicolonsp :: Parser ()
semicolonsp = word8 59 *> lwsp *> pure ()

-- | * Temporary ADTs
---------------------
data HeaderType
    = ContentH
    | EncodingH
    | IdH
    | DescriptionH
    | VersionH
    | ExtensionH ByteString
      deriving (Eq,Show,Ord)

data Header
    = Header
      { hType   :: HeaderType
      , hValue  :: ByteString
      , hParams :: M.Map ByteString ByteString
      } deriving (Eq, Show)

