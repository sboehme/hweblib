{-# LANGUAGE OverloadedStrings #-}

module Test.Parser.Rfc2822 where
--------------------------------------------------------------------------------
import           Data.Attoparsec.ByteString
import           Test.HUnit
import           Test.Parser.Parser
--------------------------------------------------------------------------------
import           Network.Parser.Rfc2234
import           Network.Parser.Rfc2822
import           Network.Parser.RfcCommon
--------------------------------------------------------------------------------

tests = TestList $ fmap TestCase lst

lst = [ test_angle_addr
      , test_name_addr
      ]

test_angle_addr
  = ae "angle_addr"
    (Just "user1@ex.org")
    (aP angle_addr "<user1@ex.org>;")

test_name_addr
  = ae "name_addr"
    (Just NameAddress {naName = Just "John Doe", naAddr = "john.doe@example.org"})
    (aP name_addr "John Doe <john.doe@example.org>;")
