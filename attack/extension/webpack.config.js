import path, { resolve } from "path";
import { fileURLToPath } from "url";
import fs from 'fs'
import copyWebpackPlugin from 'copy-webpack-plugin'
import WebpackBar from 'webpackbar'
import FriendlyErrorsWebpackPlugin from '@soda/friendly-errors-webpack-plugin';

// Determine current environment
const NODE_ENV = process.env.NODE_ENV === "production" ? "production" : "development";

// Log a friendly message
console.log(`\n==============================`);
console.log(`  Building in ${NODE_ENV.toUpperCase()} mode`);
console.log(`==============================\n`);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Dynamically generate TS entried
function getAllTsFiles(dir, extensions) {
    let results = [];
    const list = fs.readdirSync(dir); // read all the files in the directory
    list.forEach((file) => {
        const filePath = path.join(dir, file);
        const stat = fs.statSync(filePath);
        if (stat && stat.isDirectory())
            results = results.concat(getAllTsFiles(filePath, extensions)); // Concat combines array (returns new array without modifying the original array) as push appends to the end only one
        else if (extensions.some((ext) => file.endsWith(ext))) // if any extension matches
            results.push(filePath);
    })
    return results;
}

function getEntries() {
    const srcDir = path.resolve(__dirname, 'src');
    const files = getAllTsFiles(srcDir, ['.ts', '.js']);
    const entries = files.reduce((acc, file) => {
        // Create a rkey relative to src folder and remove the extension
        const relativePath = path.relative(srcDir, file);
        const entryKey = relativePath.replace(/\.ts$/, '');
        acc[entryKey] = file;
        return acc;
    }, {})
    return entries;
}

const config = {
    mode: NODE_ENV === 'production' ? 'production' : 'development',
    entry: () => getEntries(),
    output: {
        // Output goes to build/src or dev_build/src
        filename: '[name].js',
        path: path.resolve(__dirname, NODE_ENV === 'production' ? 'build' : 'dev_build', 'src'),
        clean: true,
    },
    resolve: {
        extensions: ['.ts', '.js'],
        alias: {
            '@': path.resolve(__dirname),
        }
    },
    module: {
        rules: [
            {
                test: /\.ts$/,
                use: 'ts-loader',
                exclude: /node_modules/,
            }
        ]
    },
    plugins: [
        new WebpackBar(), // Nice progress bar
        new FriendlyErrorsWebpackPlugin(), // Nice error messages
        new copyWebpackPlugin({ // Copy files 
            patterns: [
                // Copy the public folder
                {
                    from: path.resolve(__dirname, 'public'),
                    to: path.resolve(__dirname, NODE_ENV === 'production' ? 'build' : 'dev_build', 'public'),
                },
                // Copy manifest.json
                {
                    from: path.resolve(__dirname, 'manifest.json'),
                    to: path.resolve(__dirname, NODE_ENV === 'production' ? 'build' : 'dev_build'),
                },
            ],
        }),
    ]
};

export default config;