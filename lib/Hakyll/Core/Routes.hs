--------------------------------------------------------------------------------
{- | 'Routes' is part of the 'Hakyll.Core.Rules.Rules' processing pipeline.
It determines if and where the compilation result of the underlying 'Hakyll.Core.Item.Item'
being processed is written out to
(relative to the output folder as configured in 'Hakyll.Core.Configuration.destinationDirectory').

* __If there is no route for an item, the compiled item won't be written out to a file__
and so won't appear in the output site directory.

* If an item matches multiple routes, the first route will be chosen.

__Examples__

Suppose we have a markdown file @posts\/hakyll.md@. We can route/output its compilation result to
@posts\/hakyll.html@ using 'setExtension':

> -- file on disk: '<project-folder>/posts/hakyll.md'
> match "posts/*" $ do
>     route (setExtension "html") -- compilation result is written to '<output-folder>/posts/hakyll.html'
>     compile pandocCompiler
Hint: You can configure the output folder with 'Hakyll.Core.Configuration.destinationDirectory'.

If we do not want to change the extension, we can replace 'setExtension' with 'idRoute' (the simplest route available):

>     route idRoute -- compilation result is written to '<output-folder>/posts/hakyll.md'

That will route the file @posts\/hakyll.md@ from the project folder to @posts\/hakyll.md@ in the output folder.

Note: __The (output) extension says nothing about the content!__
If you set the extension to @.html@, you have to ensure that the compilation result
is indeed HTML (for example with the 'Hakyll.Web.Pandoc.pandocCompiler' to transform markdown to HTML).

Take a look at the built-in routes here for detailed usage examples.
-}
{-# LANGUAGE CPP        #-}
{-# LANGUAGE Rank2Types #-}
module Hakyll.Core.Routes
    ( Routes
    , UsedMetadata
    , runRoutes
    , idRoute
    , setExtension
    , matchRoute
    , customRoute
    , constRoute
    , gsubRoute
    , metadataRoute
    , composeRoutes
    ) where


--------------------------------------------------------------------------------
#if MIN_VERSION_base(4,9,0)
import           Data.Semigroup                 (Semigroup (..))
#endif
import           System.FilePath                (replaceExtension, normalise)


--------------------------------------------------------------------------------
import           Hakyll.Core.Identifier
import           Hakyll.Core.Identifier.Pattern
import           Hakyll.Core.Metadata
import           Hakyll.Core.Provider
import           Hakyll.Core.Util.String


--------------------------------------------------------------------------------
-- | When you ran a route, it's useful to know whether or not this used
-- metadata. This allows us to do more granular dependency analysis.
type UsedMetadata = Bool


--------------------------------------------------------------------------------
data RoutesRead = RoutesRead
    { routesProvider   :: Provider
    , routesUnderlying :: Identifier
    }


--------------------------------------------------------------------------------
-- | Type used for a route
newtype Routes = Routes
    { unRoutes :: RoutesRead -> Identifier -> IO (Maybe FilePath, UsedMetadata)
    }


--------------------------------------------------------------------------------
#if MIN_VERSION_base(4,9,0)
instance Semigroup Routes where
    (<>) (Routes f) (Routes g) = Routes $ \p id' -> do
        (mfp, um) <- f p id'
        case mfp of
            Nothing -> g p id'
            Just _  -> return (mfp, um)

instance Monoid Routes where
    mempty  = Routes $ \_ _ -> return (Nothing, False)
    mappend = (<>)
#else
instance Monoid Routes where
    mempty = Routes $ \_ _ -> return (Nothing, False)
    mappend (Routes f) (Routes g) = Routes $ \p id' -> do
        (mfp, um) <- f p id'
        case mfp of
            Nothing -> g p id'
            Just _  -> return (mfp, um)
#endif


--------------------------------------------------------------------------------
-- | Apply a route to an identifier
runRoutes :: Routes -> Provider -> Identifier
          -> IO (Maybe FilePath, UsedMetadata)
runRoutes routes provider identifier =
    unRoutes routes (RoutesRead provider identifier) identifier


--------------------------------------------------------------------------------
{- | An "identity" route that interprets the identifier (of the item being processed) as the output filepath.
This identifier is normally the filepath of the
source file being processed. See 'Hakyll.Core.Identifier.Identifier' for details.

=== __Examples__
__Route when using match__

> -- e.g. file on disk: '<project-folder>/posts/hakyll.md'
> match "posts/*" $ do           -- 'hakyll.md' source file implicitly gets filepath as identifier: 'posts/hakyll.md'
>     route idRoute              -- so compilation result is written to '<output-folder>/posts/hakyll.md'
>     compile getResourceBody
-}
idRoute :: Routes
idRoute = customRoute toFilePath


--------------------------------------------------------------------------------
{- | Create a route like 'idRoute' that interprets the identifier (of the item being processed) as the output filepath
but also sets (or replaces) the extension suffix of that path.
This identifier is normally the filepath of the
source file being processed. See 'Hakyll.Core.Identifier.Identifier' for details.

=== __Examples__
__Route with an existing extension__

> -- e.g. file on disk: '<project-folder>/posts/hakyll.md'
> match "posts/*" $ do            -- 'hakyll.md' source file implicitly gets filepath as identifier: 'posts/hakyll.md'
>     route (setExtension "html") -- compilation result is written to '<output-folder>/posts/hakyll.html'
>     compile pandocCompiler

__Route without an existing extension__

> create ["about"] $ do           -- this implicitly gets identifier: 'about'
>     route (setExtension "html") -- compilation result is written to '<output-folder>/about.html'
>     compile $ makeItem ("Hello world" :: String)
-}
setExtension :: String -> Routes
setExtension extension = customRoute $
    (`replaceExtension` extension) . toFilePath


--------------------------------------------------------------------------------
-- | Apply the route if the identifier matches the given pattern, fail
-- otherwise
matchRoute :: Pattern -> Routes -> Routes
matchRoute pattern (Routes route) = Routes $ \p id' ->
    if matches pattern id' then route p id' else return (Nothing, False)


--------------------------------------------------------------------------------
{- | Create a route where the output filepath is built with the given construction function
(that construction only gets access to the identifier of the underlying item being processed).
This identifier is normally the filepath of the
source file being processed. See 'Hakyll.Core.Identifier.Identifier' for details.
This function should almost always be used with 'matchRoute'.

=== __Examples__
__Route that appends a custom extension__

> -- e.g. file on disk: '<project-folder>/posts/hakyll.md'
> match "posts/*" $ do            -- 'hakyll.md' source file implicitly gets filepath as identifier: 'posts/hakyll.md'
>     route $ customRoute ((<> ".html") . toFilePath) -- result is written to '<output-folder>/posts/hakyll.md.html'
>     compile pandocCompiler
Note that the last part of the output file path becomes @.md.html@
-}
customRoute :: (Identifier -> FilePath) -- ^ Output filepath construction function
            -> Routes                   -- ^ Resulting route
customRoute f = Routes $ const $ \id' -> return (Just (f id'), False)


--------------------------------------------------------------------------------
{- | Create a route that writes the compiled item to the given output filepath
(ignoring any identifier or other data about the item being processed).
Warning: you should __use a specific output path only for a single file in a single compilation rule__.
Otherwise it's unclear which of the contents should be written to that route.

=== __Examples__
__Route to a specific filepath__

> create ["main"] $ do                -- implicitly gets identifier: 'main' (ignored on next line)
>     route $ constRoute "index.html" -- compilation result is written to '<output-folder>/index.html'
>     compile $ makeItem ("<h1>Hello World</h1>" :: String)
-}
constRoute :: FilePath -> Routes
constRoute = customRoute . const


--------------------------------------------------------------------------------
{- | Create a "substituting" route that searches for substrings (in the underlying identifier) that
match the given pattern and transforms them according to the given replacement function.
The identifier here is that of the underlying item being processed and is interpreted as an output filepath.
It's normally the filepath of the source file being processed. See 'Hakyll.Core.Identifier.Identifier' for details.

Hint: The name "gsub" comes from a similar function in [R](https://www.r-project.org) and
can be read as "globally substituting" (globally in the Unix sense of repeated, not just once).

=== __Examples__
__Route that replaces part of the filepath__

> -- e.g. file on disk: '<project-folder>/posts/hakyll.md'
> match "posts/*" $ do            -- 'hakyll.md' source file implicitly gets filepath as identifier: 'posts/hakyll.md'
>     route $ gsubRoute "posts/" (const "haskell/") -- result is written to '<output-folder>/haskell/hakyll.md'
>     compile getResourceBody
Note that "posts\/" is replaced with "haskell\/" in the output filepath.

__Route that removes part of the filepath__

> create ["tags/rss/bar.xml"] $ do    -- implicitly gets identifier: 'tags/rss/bar.xml'
>     route $ gsubRoute "rss/" (const "") -- result is written to '<output-folder>/tags/bar.xml'
>     compile ...
Note that "rss\/" is removed from the output filepath.
-}
gsubRoute :: String              -- ^ Pattern to repeatedly match against in the underlying identifier
          -> (String -> String)  -- ^ Replacement function to apply to the matched substrings
          -> Routes              -- ^ Resulting route
gsubRoute pattern replacement = customRoute $
    normalise . replaceAll pattern (replacement . removeWinPathSeparator) . removeWinPathSeparator . toFilePath
    where
        -- Filepaths on Windows containing `\\' will trip Regex matching, which
        -- is used in replaceAll. We normalise filepaths to have '/' as a path separator
        -- using removeWinPathSeparator


--------------------------------------------------------------------------------
{- | Wrapper function around other route construction functions to get
access to the metadata (of the underlying item being processed) and use that for the
output filepath construction.
Warning: you have to __ensure that the accessed metadata fields actually exists__.

=== __Examples__
__Route that uses a custom slug markdown metadata field__

To create a search engine optimized yet human-readable url, we can
introduce a [slug](https://en.wikipedia.org/wiki/Clean_URL#Slug) metadata field to
our files, e.g. like in the following Markdown file: 'posts\/hakyll.md'

> ---
> title: Hakyll Post
> slug: awesome-post
> ...
> ---
> In this blog post we learn about Hakyll ...

Then we can construct a route whose output filepath is based on that field:

> match "posts/*" $ do
>     route $ metadataRoute $ \meta ->         -- compilation result is written to '<output-folder>/awesome-post.html'
>         constRoute $ fromJust (lookupString "slug" meta) <> ".html"
>     compile pandocCompiler
Note how we wrap 'metadataRoute' around the 'constRoute' function and how the slug is looked up from the
markdown field to construct the output filepath.
You can use helper functions like 'Hakyll.Core.Metadata.lookupString' to access a specific metadata field.
-}
metadataRoute :: (Metadata -> Routes) -- ^ Wrapped route construction function
              -> Routes               -- ^ Resulting route
metadataRoute f = Routes $ \r i -> do
    metadata <- resourceMetadata (routesProvider r) (routesUnderlying r)
    unRoutes (f metadata) r i


--------------------------------------------------------------------------------
{- | Compose two routes where __the first route is applied before the second__.
So @f \`composeRoutes\` g@ is more or less equivalent with @g . f@.

Warning: If the first route fails (e.g. when using 'matchRoute'), Hakyll will not apply the second route 
(if you need Hakyll to try the second route, use '<>' on 'Routes' instead).

=== __Examples__
__Route that applies two transformations__

> -- e.g. file on disk: '<project-folder>/posts/hakyll.md'
> match "posts/*" $ do            -- 'hakyll.md' source file implicitly gets filepath as identifier: 'posts/hakyll.md'
>     route $ gsubRoute "posts/" (const "") `composeRoutes` setExtension "html" 
>     -- compilation result is written to '<output-folder>/hakyll.html'
>     compile pandocCompiler
The identifier here is that of the underlying item being processed and is interpreted as an output filepath.
See 'Hakyll.Core.Identifier.Identifier' for details.
Note how we first remove the "posts\/" substring from that output filepath with 'gsubRoute' 
and then replace the extension with 'setExtension'.
-}
composeRoutes :: Routes  -- ^ First route to apply
              -> Routes  -- ^ Second route to apply
              -> Routes  -- ^ Resulting route
composeRoutes (Routes f) (Routes g) = Routes $ \p i -> do
    (mfp, um) <- f p i
    case mfp of
        Nothing -> return (Nothing, um)
        Just fp -> do
            (mfp', um') <- g p (fromFilePath fp)
            return (mfp', um || um')
