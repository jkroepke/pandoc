{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE CPP #-}
{- |
   Module      : Text.Pandoc.Writers.OPML
   Copyright   : Copyright (C) 2013-2019 John MacFarlane
   License     : GNU GPL, version 2 or above

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : portable

Conversion of 'Pandoc' documents to OPML XML.
-}
module Text.Pandoc.Writers.OPML ( writeOPML) where
import Prelude
import Control.Monad.Except (throwError)
import Data.Text (Text, unpack)
import qualified Data.Text as T
import qualified Text.Pandoc.Builder as B
import Text.Pandoc.Class (PandocMonad)
import Data.Time
import Text.Pandoc.Definition
import Text.Pandoc.Error
import Text.Pandoc.Options
import Text.Pandoc.Pretty
import Text.Pandoc.Shared
import Text.Pandoc.Templates (renderTemplate)
import Text.Pandoc.Writers.HTML (writeHtml5String)
import Text.Pandoc.Writers.Markdown (writeMarkdown)
import Text.Pandoc.Writers.Shared
import Text.Pandoc.XML

-- | Convert Pandoc document to string in OPML format.
writeOPML :: PandocMonad m => WriterOptions -> Pandoc -> m Text
writeOPML opts (Pandoc meta blocks) = do
  let elements = hierarchicalize blocks
      colwidth = if writerWrapText opts == WrapAuto
                    then Just $ writerColumns opts
                    else Nothing
      meta' = B.setMeta "date" (B.str $ convertDate $ docDate meta) meta
  metadata <- metaToJSON opts
              (writeMarkdown def . Pandoc nullMeta)
              (\ils -> T.stripEnd <$> writeMarkdown def (Pandoc nullMeta [Plain ils]))
              meta'
  main <- (render colwidth . vcat) <$> mapM (elementToOPML opts) elements
  let context = defField "body" main metadata
  return $
    (if writerPreferAscii opts then toEntities else id) $
    case writerTemplate opts of
       Nothing  -> main
       Just tpl -> renderTemplate tpl context


writeHtmlInlines :: PandocMonad m => [Inline] -> m Text
writeHtmlInlines ils =
  T.strip <$> writeHtml5String def (Pandoc nullMeta [Plain ils])

-- date format: RFC 822: Thu, 14 Jul 2005 23:41:05 GMT
showDateTimeRFC822 :: UTCTime -> String
showDateTimeRFC822 = formatTime defaultTimeLocale "%a, %d %b %Y %X %Z"

convertDate :: [Inline] -> String
convertDate ils = maybe "" showDateTimeRFC822 $
  parseTimeM True defaultTimeLocale "%F" =<< normalizeDate (stringify ils)

-- | Convert an Element to OPML.
elementToOPML :: PandocMonad m => WriterOptions -> Element -> m Doc
elementToOPML _ (Blk _) = return empty
elementToOPML opts (Sec _ _num _ title elements) = do
  let isBlk :: Element -> Bool
      isBlk (Blk _) = True
      isBlk _       = False

      fromBlk :: PandocMonad m => Element -> m Block
      fromBlk (Blk x) = return x
      fromBlk _ = throwError $ PandocSomeError "fromBlk called on non-block"

      (blocks, rest) = span isBlk elements
  htmlIls <- writeHtmlInlines title
  md <- if null blocks
        then return mempty
        else do blks <- mapM fromBlk blocks
                writeMarkdown def $ Pandoc nullMeta blks
  let attrs = ("text", unpack htmlIls) :
              [("_note", unpack md) | not (null blocks)]
  o <- mapM (elementToOPML opts) rest
  return $ inTags True "outline" attrs $ vcat o
